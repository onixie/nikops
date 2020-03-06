theClusterName: theClusterEndpoint: theNode: theMasterNodes: { lib, ... }:

let serveOn = port: with lib; concatMapStringsSep "\n" (n: "server ${n.name} ${n.address}:${toString port} check") theMasterNodes;
in
{
    systemd.services.haproxy.serviceConfig = {
        Restart    = lib.mkForce "always";
        RestartSec = "5s";
    };

    services.haproxy = {

        enable = true;
        # checkme: timeout is the default value from kube-apiserver --min-request-timeout. It's better to make it configurable
        config = ''
          defaults
              timeout connect 5s
              timeout client  1800s
              timeout server  1800s

          frontend kube-apiserver-proxy
              bind ${theNode.address}:6443
              mode tcp
              default_backend kube-apiservers

          backend kube-apiservers
              mode tcp
              balance roundrobin
              option tcp-check
              ${serveOn 6443}

          frontend cfssl-server-proxy
              bind ${theNode.address}:8888
              mode tcp
              default_backend cfssl-servers

          backend cfssl-servers
              mode tcp
              balance roundrobin
              option tcp-check
              ${serveOn 8888}

          frontend etcd-proxy
              bind ${theNode.address}:2379
              mode tcp
              default_backend etcd-servers

          backend etcd-servers
              mode tcp
              balance roundrobin
              option tcp-check
              ${serveOn 2379}
        '';
    };
}
