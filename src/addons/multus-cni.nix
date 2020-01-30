{ config, lib, pkgs, options, ... }:

let
  multus-cni = with pkgs; buildGoModule rec {
    pname = "multus-cni";
    version = "master";

    src = fetchFromGitHub {
      owner = "intel";
      repo = "multus-cni";
      rev = "83556f49bd6706a885eda847210b542669279cd0";
      sha256 = "0j1m7p6qak5rnkg4khgbw562v5kln1g4163rb2q15khbqy37qyb0";
    };

    modBuildPhase = ''
    runHook preBuild
    export GIT_SSL_NO_VERIFY=true
    GOFLAGS=-insecure go mod download
    runHook postBuild
    '';

    modSha256 = "1zccbz9npbx65icz5pd84lkzn2rz4k9cwb4c2fzaq17jyn9vqz21";

    meta = with lib; {
      description = "Multus CNI enables attaching multiple network interfaces to pods in Kubernetes.";
      homepage = https://github.com/intel/multus-cni;
      license = licenses.asl20;
      platforms = [ "x86_64-linux" ];
      maintainers = with maintainers; [ onixie ];
    };
  };

  top = config.services.kubernetes;
in
with top.lib; {

  services.kubernetes = {
    flannel.enable = true;

    pki.certs = {
      multusClient = mkCert {
        name = "multus-cni";
        CN = "multus";
      };
    };

    kubelet = {
      networkPlugin = "cni";
      cni = {
        packages = options.services.kubernetes.kubelet.cni.packages.default ++ [ multus-cni ];
        config = [{
          name = "multus-cni-network";
          type = "multus";
          capabilities = {
            portMappings = true;
          };
          delegates = [ {
            name = "flannel-network";
            type = "flannel";
            delegate = {
              isDefaultGateway = true;
              bridge = "docker0";
            };
          } ];
          kubeconfig = with top.pki.certs.multusClient; mkKubeConfig "multus" {
            server = top.apiserverAddress;
            certFile = cert;
            keyFile = key;
          };
        }];
      };
      extraOpts = "--node-labels 'multus=true'";
    };

    addonManager.bootstrapAddons = with lib; {
      multus-crd  = importJSON <k8s-res/crd/multus.json>;
      multus-cr   = importJSON <k8s-res/clusterroles/multus.json>;
      multus-crb  = importJSON <k8s-res/clusterrolebindings/multus.json>;
    };
  };

  systemd = {
    services.cni-dhcp = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "cni-dhcp.socket" ];
      requires = [ "cni-dhcp.socket" ];
      description = "CNI DHCP service ";
      serviceConfig = {
        ExecStart = "/opt/cni/bin/dhcp daemon";
        Restart = "always";
        RestartSec= "10s";
      };
    };

    sockets.cni-dhcp = {
      wantedBy = [ "sockets.target" ];
      description = "CNI DHCP service socket";
      partOf = [ "cni-dhcp.service" ];
      socketConfig = {
        ListenStream = "/run/cni/dhcp.sock";
        SocketMode = "0660";
        SocketUser = "root";
        SocketGroup = "root";
        RemoveOnStop = true;
      };
    };
  };
}
