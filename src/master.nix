{ config, lib, options, nodes, ... }: 

{
  services.kubernetes = {
    roles = ["master" "node"];

    apiserver = with options.services.kubernetes.apiserver; {
      enableAdmissionPlugins = enableAdmissionPlugins.default ++ ["PodPreset" "PodSecurityPolicy"];
      runtimeConfig = runtimeConfig.default + ",settings.k8s.io/v1alpha1=true";
      allowPrivileged = true;
      #insecurePort = 8080;
      #insecureBindAddress = "127.0.0.1";
    };

    masterAddress = nodes.master.config.networking.hostName;

    addons.dashboard.enable = true;

    addonManager.bootstrapAddons = with lib; {
      apiserver-privileged-psp   = importJSON <k8s-res/podsecuritypolicies/privileged.json>;
      apiserver-privileged-crb   = importJSON <k8s-res/clusterrolebindings/privileged.json>;
      apiserver-privileged-cr    = importJSON <k8s-res/clusterroles/privileged.json>;

      apiserver-restricted-psp   = importJSON <k8s-res/podsecuritypolicies/restricted.json>;
      apiserver-restricted-crb   = importJSON <k8s-res/clusterrolebindings/restricted.json>;
      apiserver-restricted-cr    = importJSON <k8s-res/clusterroles/restricted.json>;
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
              ${nodes.master.config.networking.extraHosts}
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
