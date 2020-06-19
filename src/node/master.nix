theClusterName: theClusterEndpoint: theNode: theMasterNodes: { config, lib, options, nodes, pkgs, ... }:

with lib;

let top = config.services.kubernetes;
    cfsslAPITokenBaseName = "apitoken.secret";
    cfsslAPITokenPath = "${config.services.cfssl.dataDir}/${cfsslAPITokenBaseName}";
    etcdEnvFile = "/etc/etcd/override.env";
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
            keyFile     = <k8s-pki/ca.pem> ;
            user        = "cfssl";
            group       = "cfssl";
            permissions = "0444";
        };
        cfssl-ca-key = {
            keyFile     = <k8s-pki/ca-key.pem> ;
            user        = "cfssl";
            group       = "cfssl";
            permissions = "0400";
        };
        cfssl-api-token = {
            keyFile     = <k8s-pki/apitoken.secret> ;
            user        = "cfssl";
            group       = "cfssl";
            permissions = "0400";
        };
        kubernetes-sa-signer = {
            keyFile     = <k8s-pki/sa.pem> ;
            user        = "kubernetes";
            group       = "nogroup";
            permissions = "0444";
        };
        kubernetes-sa-signer-key = {
            keyFile     = <k8s-pki/sa-key.pem> ;
            user        = "kubernetes";
            group       = "nogroup";
            permissions = "0400";
        };
    };

    # services.cfssl = {
    # dataDir = "${<k8s-res/pki>}"; # bug: nixos/kubernetes has problem to generate cfssl cert if we make pki readonly
    # ca      = "${<k8s-res/pki/ca.pem>}";
    # caKey   = "${<k8s-res/pki/ca-key.pem>}"; # limitation: nix store is insecure
    # };

    # hack: workaround for the bug describe above
    systemd.services.cfssl = {
      preStart = mkBefore ''
          if test ! -f /run/keys/cfssl-ca && test ! -f ${top.pki.caCertPathPrefix}.pem; then
            exit 1
          fi

          if test ! -f /run/keys/cfssl-ca-key && test ! -f ${top.pki.caCertPathPrefix}-key.pem; then
            exit 1
          fi

          if test ! -f /run/keys/cfssl-api-token && test ! -f ${cfsslAPITokenPath}; then
            exit 1
          fi

          set +e

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

          set -e
      '';
      serviceConfig = {
        StateDirectory = mkForce "cfssl"; # checkme: should fix in upstream. Value to StateDirectory must be relative path.
        StateDirectoryMode = mkForce 711;
        StartLimitInterval = mkForce 0;
        RestartSec = mkForce "10s";
      };
    };

    systemd.services.certmgr = {
      preStart = mkBefore ''
          if test ! -f /run/keys/kubernetes-sa-signer && test ! -f ${top.secretsPath}/service-account.pem; then
            exit 1
          fi

          if test ! -f /run/keys/kubernetes-sa-signer-key && test ! -f ${top.secretsPath}/service-account-key.pem; then
            exit 1
          fi

          if test ! -f ${top.pki.caCertPathPrefix}.pem || test ! -f ${cfsslAPITokenPath}; then
            exit 1
          fi

          set +e

          mkdir -p ${top.secretsPath} && chmod 0755 ${top.secretsPath}

          test -s ${top.pki.caCertPathPrefix}.pem && ln -fs ${top.pki.caCertPathPrefix}.pem ${top.secretsPath}/ca.pem
          test -s ${cfsslAPITokenPath} && ln -fs ${cfsslAPITokenPath} ${top.secretsPath}/apitoken.secret

          updateKey() {
          test -f "$3" && chmod u+w "$3"
          cp -upd "/run/keys/$2" "$3" && chown kubernetes:nogroup "$3" && chmod $1 "$3"
          }
          updateKey 0444 kubernetes-sa-signer     ${top.secretsPath}/service-account.pem
          updateKey 0400 kubernetes-sa-signer-key ${top.secretsPath}/service-account-key.pem

          set -e
      '';
      serviceConfig = {
        StartLimitInterval = mkForce 0;
      };
    };

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
          StartLimitInterval = mkForce 0;
          RestartSec = "15s";
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
    systemd.services.etcd= {
      serviceConfig = {
        ConfigurationDirectory = "etcd";
        EnvironmentFile = "-${etcdEnvFile}";
        ExecStartPre  = pkgs.writeScript "pre-etcd-bootstrap" ''
            #!${pkgs.stdenv.shell}

            export ETCDCTL_API="3"
            export ETCDCTL_CACERT="${top.secretsPath}/ca.pem"
            export ETCDCTL_CERT="${top.secretsPath}/etcd.pem"
            export ETCDCTL_KEY="${top.secretsPath}/etcd-key.pem"
            export ETCDCTL_ENDPOINTS="https://${theClusterName}:2379"

            if test ! -f "${top.secretsPath}/etcd.pem" || test ! -f "${top.secretsPath}/etcd-key.pem"; then
               echo "Waiting for PKI initialization..."
               exit 1
            fi

            if ! ${pkgs.etcd}/bin/etcdctl member list >/dev/null 2>&1; then
               echo "Bootstrapping etcd cluster for the first time."
               exit 0
            fi

            if ${pkgs.etcd}/bin/etcdctl member list | grep ${theNode.name}; then
               exit 0
            fi

            if ${pkgs.etcd}/bin/etcdctl member add ${theNode.name} --peer-urls="https://${theNode.address}:2380"; then
               rm ${config.services.etcd.dataDir}/* -rf
               ${pkgs.coreutils}/bin/echo ETCD_INITIAL_CLUSTER_STATE=existing > ${etcdEnvFile}
            fi
        '';
        ExecStartPost = pkgs.writeScript "post-etcd-bootstrap" ''
            #!${pkgs.stdenv.shell}

            if ! grep "^ETCD_INITIAL_CLUSTER_STATE=existing$" ${etcdEnvFile}; then
               ${pkgs.coreutils}/bin/echo ETCD_INITIAL_CLUSTER_STATE=existing > ${etcdEnvFile}
            fi
        '';
        StartLimitInterval = mkForce 0;
        RestartSec = "10s";
      };
    };

    systemd.services.kubelet = {
      serviceConfig = {
        StartLimitInterval = mkForce 0;
      };
    };

    systemd.services.kube-apiserver = {
      serviceConfig = {
        StartLimitInterval = mkForce 0;
      };
    };

    services.kubernetes = {
        # dataDir = "/etc/kubernetes";
        # secretsPath = config.services.kubernetes.dataDir + "/pki";
        pki = {
            genCfsslCACert   = false;
            genCfsslAPIToken = false;
            # caCertPathPrefix = "${<k8s-res/pki>}/ca";
            pkiTrustOnBootstrap = false;
            certs.serviceAccount = null;
        };

        roles = [ "master" ] ++ (if elem "worker" theNode.roles then [ "node" ] else []);

        apiserver = with options.services.kubernetes.apiserver; {
            advertiseAddress = theNode.address;
            enableAdmissionPlugins = enableAdmissionPlugins.default ++ ["PodPreset" "PodSecurityPolicy"];
            runtimeConfig = runtimeConfig.default + ",settings.k8s.io/v1alpha1=true";
            allowPrivileged = true;
            extraOpts = mkDefault ''
              --requestheader-client-ca-file=${top.secretsPath}/ca.pem \
              --requestheader-extra-headers-prefix=X-Remote-Extra- \
              --requestheader-group-headers=X-Remote-Group \
              --requestheader-username-headers=X-Remote-User \
              --requestheader-allowed-names=""
            '';
            serviceAccountKeyFile = "${top.secretsPath}/service-account.pem";
        };
        controllerManager = let kc = "${top.lib.mkKubeConfig "kube-controller-manager" top.controllerManager.kubeconfig}"; in {
            serviceAccountKeyFile = "${top.secretsPath}/service-account-key.pem";
            extraOpts = mkDefault ''
              --authentication-kubeconfig=${kc} \
              --authorization-kubeconfig=${kc} 
            '';
        };
        scheduler = let kc = "${top.lib.mkKubeConfig "kube-scheduler" top.scheduler.kubeconfig}"; in {
            extraOpts = mkDefault ''
              --authentication-kubeconfig=${kc} \
              --authorization-kubeconfig=${kc} 
            '';
        };
        kubelet = {
          extraOpts = mkForce "--resolv-conf /run/systemd/resolve/resolv.conf";
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

        addonManager.addons.coredns-cm = with top.addons; mkForce {
        apiVersion = "v1";
        kind = "ConfigMap";
        metadata = {
          labels = {
            "addonmanager.kubernetes.io/mode" = dns.reconcileMode;
            k8s-app = "kube-dns";
            "kubernetes.io/cluster-service" = "true";
          };
          name = "coredns";
          namespace = "kube-system";
        };
        data = {
          Corefile = ''
          .:${toString 10053} {
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
          }
          '';
        };
      };
    };
}
