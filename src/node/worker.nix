theClusterName: theClusterEndpoint: theNode: theMasterNodes: { config, lib, ... }:

with lib;
let top = config.services.kubernetes;
in
{
    deployment.keys = {
        cfssl-ca = {
            keyFile     = <k8s-pki/ca.pem> ;
            user        = "root";
            group       = "root";
            permissions = "0444";
        };

        cfssl-api-token = {
            keyFile     = <k8s-pki/apitoken.secret> ;
            user        = "root";
            group       = "root";
            permissions = "0400";
        };
    };

    systemd.services.cfssl.enable = false; # checkme: nixos/kubernetes should disable this on worker

    systemd.services.kube-certmgr-bootstrap.script = mkForce ''
      test -f ${top.secretsPath}/ca.pem && chmod u+w ${top.secretsPath}/ca.pem
      cp -upd /run/keys/cfssl-ca        ${top.secretsPath}/ca.pem
      chown root:root ${top.secretsPath}/ca.pem && chmod 0444 ${top.secretsPath}/ca.pem

      test -f ${top.secretsPath}/apitoken.secret && chmod u+w ${top.secretsPath}/apitoken.secret
      cp -upd /run/keys/cfssl-api-token ${top.secretsPath}/apitoken.secret
      chown root:root ${top.secretsPath}/apitoken.secret && chmod 0400 ${top.secretsPath}/apitoken.secret
    '';

    services.kubernetes = {
        roles = [ "node" ];
        masterAddress = theClusterName;
        pki.pkiTrustOnBootstrap = false;
    };
}
