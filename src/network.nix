network: theNode: otherNodes: { lib, ... }:

with lib;

let allNodes = unique ([ theNode ] ++ otherNodes);
    proxy    = import <k8s/proxy>;
in mkMerge
    [
        {
            deployment.targetHost = theNode.address;

            networking.hostName = theNode.name;
            networking.usePredictableInterfaceNames = false;
            networking.interfaces.eth0.ipv4.addresses = [ {
                address = theNode.address;
                prefixLength = toInt (elemAt (splitString "/" network.subnet) 1);
            } ];

            networking.defaultGateway = network.gateway;
            networking.nameservers    = network.dns;
            networking.extraHosts     = concatMapStringsSep "\n" (node : "${node.address} ${node.name}") allNodes;

            networking.firewall.enable = false;
        }

        (mkIf (hasAttr "url" proxy && proxy.url != null)
            {
                networking.proxy.default  = proxy.url;
                networking.proxy.noProxy  = "127.0.0.1,localhost,${network.subnet},${concatMapStringsSep "," (node : node.name) allNodes}";
            }
        )

        (mkIf (hasAttr "crt" proxy && proxy.crt != null)
            {
                security.pki.certificates = [ proxy.crt ];
            }
        )
    ]
