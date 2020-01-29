theClusterName: theClusterEndpoint: theNode: theMasterNodes: { config, ... }:

let top = config.services.kubernetes;
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

    systemd.services.kube-certmgr-bootstrap.preStart = ''
      ln -fs /run/keys/cfssl-ca        ${top.secretsPath}/ca.pem
      ln -fs /run/keys/cfssl-api-token ${top.secretsPath}/apitoken.secret
    '';

    systemd.services.cfssl.enable = false; # checkme: nixos/kubernetes should disable this on worker

    services.kubernetes = {
        roles = [ "node" ];
        masterAddress = theClusterName;
    };
}
