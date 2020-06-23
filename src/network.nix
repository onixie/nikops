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
            systemd.network = {
              enable = true;
              links."10-flannel" = {
                matchConfig.OriginalName = "flannel*";
                linkConfig.MACAddressPolicy="none";
              };
            };

            networking.nameservers    = theNetwork.dns;
            networking.extraHosts     = ''
            ${theClusterEndpoint} ${theClusterName} ${theClusterName}.default ${theClusterName}.default.svc ${theClusterName}.default.svc.cluster ${theClusterName}.default.svc.cluster.local
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
                    mtu = 1420;
                };
                networking.defaultGateway = theNetwork.gateway;
            }
        )

        (mkIf (hasAttr "url" theProxy && theProxy.url != null)
            {
                networking.proxy.default  = theProxy.url;
                networking.proxy.noProxy  = "127.0.0.1,localhost,${theClusterName},*.svc.cluster.local,${theNetwork.subnet},${concatMapStringsSep "," (n: n.name) theNodes},${if hasAttr "exl" theProxy && theProxy.exl != null then theProxy.exl else ""}";
            }
        )

        (mkIf (hasAttr "crt" theProxy && theProxy.crt != null)
            {
                security.pki.certificates = [ theProxy.crt ];
            }
        )
    ]
