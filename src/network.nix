theClusterName: theClusterEndpoint: theNode: theNodes: theNetwork: { lib, config, ... }:

with lib;

let theProxy = import <k8s/proxy> ;
    theNetIF = if config.deployment.targetEnv == "virtualbox"
               then "enp0s3"
               else
                   if config.deployment.targetEnv == "libvirtd"
                   then "enp0s2"
                   else null;
in mkMerge
    [
        {
            networking.hostName    = theNode.name;
            networking.privateIPv4 = mkForce theNode.address; # bug? nixops should respect this configuration.
            deployment.targetHost  = theNode.address;
            # networking.usePredictableInterfaceNames = false; # work with virtualbox but need to reboot once

            services.flannel.iface    = theNetIF;

            networking.nameservers    = theNetwork.dns;
            networking.extraHosts     = ''
            ${theClusterEndpoint} ${theClusterName}
            ${concatMapStringsSep "\n" (n: "${n.address} ${n.name}") theNodes}
            '';

            networking.firewall.enable = false;
        }

        (mkIf (theNetwork ? managed && theNetwork.managed == false)
            {
                networking.interfaces."${theNetIF}" = {
                    ipv4.addresses = [ {
                        address = theNode.address;
                        prefixLength = toInt (elemAt (splitString "/" theNetwork.subnet) 1);
                    } ];
                    mtu = 1500;
                };
                networking.defaultGateway = theNetwork.gateway;
            }
        )

        (mkIf (hasAttr "url" theProxy && theProxy.url != null)
            {
                networking.proxy.default  = theProxy.url;
                networking.proxy.noProxy  = "127.0.0.1,localhost,${theClusterName},${theNetwork.subnet},${concatMapStringsSep "," (n: n.name) theNodes}";
            }
        )

        (mkIf (hasAttr "crt" theProxy && theProxy.crt != null)
            {
                security.pki.certificates = [ theProxy.crt ];
            }
        )
    ]
