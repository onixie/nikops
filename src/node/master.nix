theClusterName: theClusterEndpoint: theNode: theMasterNodes: { config, lib, options, nodes, pkgs, ... }:

with lib;

let top = config.services.kubernetes;
    cfsslAPITokenBaseName = "apitoken.secret";
    cfsslAPITokenPath = "${config.services.cfssl.dataDir}/${cfsslAPITokenBaseName}";
in
{
    environment = {
        systemPackages = with pkgs;[ vim emacs kubectl ];
        variables = { EDITOR = "vim"; };
    };

    programs.bash = {

        shellAliases = {
	        k = "kubectl --server=https://${theClusterName}:6443 --kubeconfig=/etc/${top.pki.etcClusterAdminKubeconfig}";
            e = "ETCDCTL_API=3 etcdctl --endpoints=https://${theClusterName}:2379 --cacert=${top.secretsPath}/ca.pem --cert=${top.secretsPath}/etcd.pem --key=${top.secretsPath}/etcd-key.pem";
        };

        interactiveShellInit = concatStringsSep "\n" [
            "source <(kubectl completion bash) && complete -F __start_kubectl k"
        ];
    };

    # systemd.tmpfiles.rules = [ "d ${config.services.kubernetes.dataDir} 0755 kubernetes kubernetes -" ]; # bug from upstream, this should be fixed in nixpkgs/nixos
    users.users.cfssl.extraGroups = [ "keys" ];

    deployment.keys = {
        cfssl-ca = {
            keyFile     = <k8s-res/pki/ca.pem> ;
            user        = "cfssl";
            group       = "cfssl";
            permissions = "0444";
        };
        cfssl-ca-key = {
            keyFile     = <k8s-res/pki/ca-key.pem> ;
            user        = "cfssl";
            group       = "cfssl";
            permissions = "0400";
        };
        cfssl-api-token = {
            keyFile     = <k8s-res/pki/apitoken.secret> ;
            user        = "cfssl";
            group       = "cfssl";
            permissions = "0400";
        };
    };

    # services.cfssl = {
    # dataDir = "${<k8s-res/pki>}"; # bug: nixos/kubernetes has problem to generate cfssl cert if we make pki readonly
    # ca      = "${<k8s-res/pki/ca.pem>}";
    # caKey   = "${<k8s-res/pki/ca-key.pem>}"; # limitation: nix store is insecure
    # };

    # hack: workaround for the bug describe above
    systemd.services.cfssl.preStart = mkBefore ''
      set -e

      updateKey() {
        test -f "$3" && chmod u+w "$3"
        cp -upd "/run/keys/$2" "$3" && chown cfssl:cfssl "$3" && chmod $1 "$3"
      }

      # Replacement for genCfsslCACert
      #ln -fs /run/keys/cfssl-ca ${top.pki.caCertPathPrefix}.pem
      updateKey 0444    cfssl-ca ${top.pki.caCertPathPrefix}.pem

      #ln -fs /run/keys/cfssl-ca-key ${top.pki.caCertPathPrefix}-key.pem
      updateKey 0400    cfssl-ca-key ${top.pki.caCertPathPrefix}-key.pem

      # Replacement for genCfsslAPIToken
      #ln -fs /run/keys/cfssl-api-token ${cfsslAPITokenPath}
      updateKey 0400    cfssl-api-token ${cfsslAPITokenPath}

    '';

    systemd.services.cfssl.serviceConfig = {
      StateDirectory = mkForce "cfssl"; # checkme: should fix in upstream. Value to StateDirectory must be relative path.
      StateDirectoryMode = mkForce 711;
    };

    systemd.services.kube-certmgr-bootstrap.script = mkForce ''
      ln -fs ${top.pki.caCertPathPrefix}.pem ${top.secretsPath}/ca.pem
      ln -fs ${cfsslAPITokenPath} ${top.secretsPath}/apitoken.secret
    '';

    systemd.services.etcd-runtime-reconfigure = {
        description = "Etcd auto runtime reconfiguration";
        wantedBy = [ "etcd.service" ];
        after = [ "etcd.service" ];
        environment = {
            ETCDCTL_API    = "3";
            ETCDCTL_CACERT = "${top.secretsPath}/ca.pem";
            ETCDCTL_CERT   = "${top.secretsPath}/etcd.pem";
            ETCDCTL_KEY    = "${top.secretsPath}/etcd-key.pem";
            ETCDCTL_ENDPOINTS = "https://${theClusterName}:2379";
        };
        script = let members = concatMapStringsSep "\\n" (n: "${n.name},${concatStringsSep "," nodes."${n.name}".config.services.etcd.listenPeerUrls}") theMasterNodes; in ''
        set +e
        MEMBERS_CUR=$(${pkgs.etcd}/bin/etcdctl member list -w=simple | cut -f1,3 -d',' | tr -d ' ')
        MEMBERS_ADD=$(comm -13 <(echo "$MEMBERS_CUR" | cut -f2 -d',' | sort) <(printf "${members}" | cut -f1 -d',' | sort))
        MEMBERS_REM=$(comm -23 <(echo "$MEMBERS_CUR" | cut -f2 -d',' | sort) <(printf "${members}" | cut -f1 -d',' | sort))

        for mr in $MEMBERS_REM; do
            mid=$(echo "$MEMBERS_CUR" | grep $mr | cut -f1 -d',')

            ${pkgs.etcd}/bin/etcdctl member remove $mid
        done

        for ma in $MEMBERS_ADD; do
            if [[ "$ma" == "${theNode.name}" ]]; then
                ${pkgs.etcd}/bin/etcdctl member add $ma --peer-urls="$(printf "${members}" | grep $ma | cut -f2 -d',')"
                rm "${config.services.etcd.dataDir}/member" -rf
                systemctl restart etcd
            fi
        done
        '';

        serviceConfig = {
            RestartSec = "30s";
            Restart = "always";
        };
    };

    #systemd.services.etcd.environment.ETCD_INITIAL_CLUSTER_STATE = mkForce "existing";

    systemd.services.kube-node-role-reconfigure = {
        description = "K8s node role auto reconfiguration";
        wantedBy = [ "kubernetes.target" ];
        after = [ "kubernetes.target" ];
        environment = {
            KUBECONFIG = "/etc/kubernetes/cluster-admin.kubeconfig";
        };
        script = let pureMasters = filter (n: ! elem "worker" n.roles) theMasterNodes;
                     workMasters = filter (n:   elem "worker" n.roles) theMasterNodes;
                     workers     = filter (n: n.config.services.kubernetes.roles == [ "node" ]) (attrValues nodes);
                 in ''
        set +e

        for mn in ${concatMapStringsSep " " (m: m.name) pureMasters}; do
           ${pkgs.kubectl}/bin/kubectl taint --overwrite nodes $mn unschedulable=true:NoSchedule
           ${pkgs.kubectl}/bin/kubectl taint --overwrite nodes $mn node-role.kubernetes.io/master=true:NoExecute
           ${pkgs.kubectl}/bin/kubectl label --overwrite nodes $mn node-role.kubernetes.io/master=true
           ${pkgs.kubectl}/bin/kubectl label --overwrite nodes $mn node-role.kubernetes.io/worker-
        done

        for mn in ${concatMapStringsSep " " (m: m.name) workMasters}; do
           ${pkgs.kubectl}/bin/kubectl taint --overwrite nodes $mn unschedulable-
           ${pkgs.kubectl}/bin/kubectl taint --overwrite nodes $mn node-role.kubernetes.io/master-
           ${pkgs.kubectl}/bin/kubectl label --overwrite nodes $mn node-role.kubernetes.io/master=true
           ${pkgs.kubectl}/bin/kubectl label --overwrite nodes $mn node-role.kubernetes.io/worker=true
        done

        for mn in ${concatMapStringsSep " " (m: m.config.networking.hostName) workers}; do
           ${pkgs.kubectl}/bin/kubectl taint --overwrite nodes $mn unschedulable-
           ${pkgs.kubectl}/bin/kubectl taint --overwrite nodes $mn node-role.kubernetes.io/master-
           ${pkgs.kubectl}/bin/kubectl label --overwrite nodes $mn node-role.kubernetes.io/master-
           ${pkgs.kubectl}/bin/kubectl label --overwrite nodes $mn node-role.kubernetes.io/worker=true
        done
        '';

        serviceConfig = {
            RestartSec = "30s";
            Restart = "always";
        };
    };

    services.etcd = {
        initialAdvertisePeerUrls = mkForce ["https://${theNode.address}:2380"];
        listenPeerUrls = mkForce ["https://${theNode.address}:2380"];
        initialCluster = mkForce (map (n: "${n.name}=https://${n.address}:2380") theMasterNodes);

        advertiseClientUrls = mkForce ["https://${theNode.address}:2379"];
        listenClientUrls = ["https://${theNode.address}:2379"]; # dont mkForce because the default 127.0.0.1 is expected.
        name = theNode.name;
    };
    systemd.services.etcd.serviceConfig = {
        RestartSec = "5s";
        Restart = "on-failure";
    };

    services.kubernetes = {
        # dataDir = "/etc/kubernetes";
        # secretsPath = config.services.kubernetes.dataDir + "/pki";
        pki = {
            genCfsslCACert   = false;
            genCfsslAPIToken = false;
            # caCertPathPrefix = "${<k8s-res/pki>}/ca";
            pkiTrustOnBootstrap = false;
        };

        roles = [ "master" ] ++ (if elem "worker" theNode.roles then [ "node" ] else []);

        apiserver = with options.services.kubernetes.apiserver; {
            advertiseAddress = theNode.address;
            enableAdmissionPlugins = enableAdmissionPlugins.default ++ ["PodPreset" "PodSecurityPolicy"];
            runtimeConfig = runtimeConfig.default + ",settings.k8s.io/v1alpha1=true";
            allowPrivileged = true;
        };

        apiserverAddress = mkForce "https://${theNode.address}:${toString top.apiserver.securePort}"; # bugs in nixos/kubernetes, port is missing if use advertise

        masterAddress = theClusterName;

        addons.dashboard.enable = true;

        addonManager.bootstrapAddons = {
            apiserver-privileged-psp = importJSON <k8s-res/podsecuritypolicies/privileged.json> ;
            apiserver-restricted-psp = importJSON <k8s-res/podsecuritypolicies/restricted.json> ;

            apiserver-privileged-cr  = importJSON <k8s-res/clusterroles/privileged.json> ;
            apiserver-restricted-cr  = importJSON <k8s-res/clusterroles/restricted.json> ;

            apiserver-privileged-crb = importJSON <k8s-res/clusterrolebindings/privileged.json> ;
            apiserver-restricted-crb = importJSON <k8s-res/clusterrolebindings/restricted.json> ;
        };

        addonManager.addons = with top.addons; {
            coredns-cm.data.Corefile = ".:${toString 10053} {
            errors
            health :${toString 10054}
            kubernetes ${dns.clusterDomain} in-addr.arpa ip6.arpa {
              pods insecure
              upstream
              fallthrough in-addr.arpa ip6.arpa
            }
            hosts {
              ${nodes."${theNode.name}".config.networking.extraHosts}
              fallthrough
            }
            prometheus :${toString 10055}
            forward . /etc/resolv.conf
            cache 30
            loop
            reload
            loadbalance
            }";
        };
    };
}
