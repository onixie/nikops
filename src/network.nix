network: theNode: otherNodes: { lib, ... }:

let allNodes = lib.unique ([ theNode ] ++ otherNodes);
in {
  deployment.targetHost = theNode.address;

  networking.hostName = theNode.name;
  networking.interfaces.ens2.ipv4.addresses = [ {
    address = theNode.address;
    prefixLength = network.mask;
  } ];

  networking.defaultGateway = network.gateway;
  networking.nameservers    = network.dns;
  networking.extraHosts     = lib.concatMapStringsSep "\n" (node : "${node.address} ${node.name}") allNodes;

  networking.proxy.default  = network.proxy.url;
  networking.proxy.noProxy  = "127.0.0.1,localhost,${network.address}/${toString network.mask},${lib.concatMapStringsSep "," (node : node.name) allNodes}";
  security.pki.certificates = [ network.proxy.cert ];

  networking.firewall.enable = false;
}
