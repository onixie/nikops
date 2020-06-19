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

    systemd.services.certmgr = {
      preStart = mkBefore ''
          if test ! -f /run/keys/cfssl-ca && test ! -f ${top.secretsPath}/ca.pem; then
            exit 1
          fi

          if test ! -f /run/keys/cfssl-api-token && test ! -f ${top.secretsPath}/apitoken.secret; then
            exit 1
          fi

          set +e

          mkdir -p ${top.secretsPath} && chmod 0755 ${top.secretsPath}

          test -f ${top.secretsPath}/ca.pem && chmod u+w ${top.secretsPath}/ca.pem
          cp -upd /run/keys/cfssl-ca        ${top.secretsPath}/ca.pem
          chown root:root ${top.secretsPath}/ca.pem && chmod 0444 ${top.secretsPath}/ca.pem

          test -f ${top.secretsPath}/apitoken.secret && chmod u+w ${top.secretsPath}/apitoken.secret
          test ! -s ${top.secretsPath}/apitoken.secret && rm ${top.secretsPath}/apitoken.secret
          cp -upd /run/keys/cfssl-api-token ${top.secretsPath}/apitoken.secret
          chown root:root ${top.secretsPath}/apitoken.secret && chmod 0400 ${top.secretsPath}/apitoken.secret

          set -e
      '';
    };

    systemd.services.kubelet = {
      serviceConfig = {
        StartLimitInterval = mkForce 0;
      };
    };

    services.kubernetes = {
        roles = [ "node" ];
        masterAddress = theClusterName;
        pki.pkiTrustOnBootstrap = false;
    };
}
