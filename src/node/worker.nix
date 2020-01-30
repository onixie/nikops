theClusterName: theClusterEndpoint: theNode: theMasterNodes: { config, lib, ... }:

with lib;
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

    systemd.services.cfssl.enable = false; # checkme: nixos/kubernetes should disable this on worker

    systemd.services.kube-certmgr-bootstrap.script = mkForce ''
      cp -pd /run/keys/cfssl-ca        ${top.secretsPath}/ca.pem
      ln -fs /run/keys/cfssl-api-token ${top.secretsPath}/apitoken.secret
    '';

    services.kubernetes = {
        roles = [ "node" ];
        masterAddress = theClusterName;
        pki.pkiTrustOnBootstrap = false;
    };
}
