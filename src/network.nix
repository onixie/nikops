network: theNode: otherNodes: { lib, config, ... }:

with lib;

let allNodes = unique ([ theNode ] ++ otherNodes);
    proxy    = import <k8s/proxy> ;
    iface    = if config.deployment.targetEnv == "virtualbox"
               then "enp0s8"
               else null;
in mkMerge
    [
        {
            networking.hostName    = theNode.name;
            networking.privateIPv4 = mkForce theNode.address; # bug? nixops should respect this configuration.
            deployment.targetHost  = theNode.address;

            # networking.usePredictableInterfaceNames = false; # work with virtualbox but need to reboot once
            # networking.defaultGateway = network.gateway; # not work for virtualbox

            networking.interfaces."${iface}".ipv4.addresses = [ {
                address = theNode.address;
                prefixLength = toInt (elemAt (splitString "/" network.subnet) 1);
            } ];

            services.flannel.iface    = iface;

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
