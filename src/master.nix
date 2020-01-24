theNode: { config, lib, options, nodes, pkgs, ... }:

with lib;

let masterNodes  = filter (n: any (r: r == "master") n.config.services.kubernetes.roles ) (attrValues nodes);
    cfsslAPITokenBaseName = "apitoken.secret";
    cfsslAPITokenPath = "${config.services.cfssl.dataDir}/${cfsslAPITokenBaseName}";
in
{
    environment = {
        systemPackages = with pkgs;[ vim emacs kubectl ];
        variables = { EDITOR = "vim"; };
    };

    programs.bash = {

        shellAliases = with config.services.kubernetes; {
            s = "systemctl";
	        k = "kubectl --kubeconfig=/etc/${pki.etcClusterAdminKubeconfig}";
            e = "ETCDCTL_API=3 etcdctl --endpoints=https://etcd.local:2379 --cacert=${secretsPath}/ca.pem --cert=${secretsPath}/etcd.pem --key=${secretsPath}/etcd-key.pem";
        };

        interactiveShellInit = concatStringsSep "\n" [
            "source <(kubectl completion bash) && complete -F __start_kubectl k"
            ". ${pkgs.systemd}/share/bash-completion/completions/systemctl && complete -F _systemctl s"
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
    systemd.services.cfssl.preStart = with config.services.kubernetes.pki; mkBefore
        ''
      set -e

      # Replacement for genCfsslCACert
      ln -fs /run/keys/cfssl-ca     ${caCertPathPrefix}.pem
      ln -fs /run/keys/cfssl-ca-key ${caCertPathPrefix}-key.pem

      # Replacement for genCfsslAPIToken
      ln -fs /run/keys/cfssl-api-token ${cfsslAPITokenPath}

    '';

    services.etcd = {
        initialAdvertisePeerUrls = mkForce ["https://${theNode.address}:2380"];
        listenPeerUrls = mkForce ["https://${theNode.address}:2380"];
        initialCluster = mkForce (map (m: with m.config.networking; "${hostName}=https://${privateIPv4}:2380") masterNodes);

        advertiseClientUrls = mkForce ["https://${theNode.address}:2379"];
        listenClientUrls = ["https://${theNode.address}:2379"]; # dont mkForce because the default 127.0.0.1 is expected.
        name = theNode.name;
    };

    services.kubernetes = {
        # dataDir = "/etc/kubernetes";
        # secretsPath = config.services.kubernetes.dataDir + "/pki";
        pki = {
            genCfsslCACert   = false;
            genCfsslAPIToken = false;
            # caCertPathPrefix = "${<k8s-res/pki>}/ca";
        };

        roles = ["master" "node"];

        apiserver = with options.services.kubernetes.apiserver; {
            advertiseAddress = theNode.address;
            enableAdmissionPlugins = enableAdmissionPlugins.default ++ ["PodPreset" "PodSecurityPolicy"];
            runtimeConfig = runtimeConfig.default + ",settings.k8s.io/v1alpha1=true";
            allowPrivileged = true;
        };

        apiserverAddress = mkForce "https://${theNode.address}:${toString config.services.kubernetes.apiserver.securePort}"; # bugs in nixos/kubernetes, port is missing if use advertise

        masterAddress = nodes.kubernetes.config.networking.hostName;

        addons.dashboard.enable = true;

        addonManager.bootstrapAddons = {
            apiserver-privileged-psp = importJSON <k8s-res/podsecuritypolicies/privileged.json> ;
            apiserver-restricted-psp = importJSON <k8s-res/podsecuritypolicies/restricted.json> ;

            apiserver-privileged-cr  = importJSON <k8s-res/clusterroles/privileged.json> ;
            apiserver-restricted-cr  = importJSON <k8s-res/clusterroles/restricted.json> ;

            apiserver-privileged-crb = importJSON <k8s-res/clusterrolebindings/privileged.json> ;
            apiserver-restricted-crb = importJSON <k8s-res/clusterrolebindings/restricted.json> ;
        };

        addonManager.addons = with config.services.kubernetes.addons; {
            coredns-cm.data.Corefile = ".:${toString 10053} {
            errors
            health :${toString 10054}
            kubernetes ${dns.clusterDomain} in-addr.arpa ip6.arpa {
              pods insecure
              upstream
              fallthrough in-addr.arpa ip6.arpa
            }
            hosts {
              ${nodes.master1.config.networking.extraHosts}
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
