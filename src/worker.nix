theNode: { lib, config, nodes, ... }:
with lib;

let masterNodes   = filter (n: any (r: r == "master") n.config.services.kubernetes.roles ) (attrValues nodes);
    cfsslAPITokenBaseName = "apitoken.secret";
    cfsslAPITokenPath = "${config.services.kubernetes.secretsPath}/${cfsslAPITokenBaseName}";
in
{
    deployment.keys = {
        cfssl-ca = {
            keyFile     = <k8s-res/pki/ca.pem> ;
            user        = "root";
            group       = "root";
            permissions = "0444";
        };

        cfssl-api-token = {
            keyFile     = <k8s-res/pki/apitoken.secret> ;
            user        = "root";
            group       = "root";
            permissions = "0400";
        };
    };

    systemd.services.cfssl.enable = false; # checkme: nixos/kubernetes should disable this on worker

    systemd.services.kube-certmgr-bootstrap.preStart = ''
      ln -fs /run/keys/cfssl-ca        ${config.services.kubernetes.secretsPath}/ca.pem
      ln -fs /run/keys/cfssl-api-token ${cfsslAPITokenPath}
    '';

    services.kubernetes = {
        roles = ["node"];
        masterAddress =  nodes.kubernetes.config.networking.hostName; # (head masterNodes).config.networking.hostName;
    };
}
