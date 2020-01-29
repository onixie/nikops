theCluster:

with import <nixpkgs/lib> ;

let isLB     = n: elem "loadbalancer" n.roles;
    isMaster = n: elem "master"       n.roles && ! isLB n;

    theName = theCluster.name or "kubernetes";

    theNetwork = theCluster.network;

    theDeployment = theCluster.deployment or {
        targetEnv             = "virtualbox";
        virtualbox.headless   = true;
        virtualbox.memorySize = 2048;
        virtualbox.vcpu       = 2;
    };

    theNodes = mapAttrs (k: n: n // {
        name = k;
        nix  = if isLB n
               then <k8s/loadbalancer>
               else
                   if isMaster n
                   then <k8s/master>
                   else <k8s/worker> ;
    }) (filterAttrs (k: _: ! (elem k [ "name" "network" "deployment" ])) theCluster);

    theMasterNodes = filterAttrs (_: isMaster) theNodes;
    theLBNodes     = filterAttrs (_: isLB    ) theNodes;

    theEndpoint = (head (attrValues (if theLBNodes != {} then theLBNodes else theMasterNodes))).address;
in

mapAttrs (_: theNode:
    (usingArgs@{ pkgs, config, lib, options, nodes, ... }:
        lib.mkMerge (map (f: f usingArgs) [
            (import theNode.nix   theName theEndpoint theNode (attrValues theMasterNodes))
            (import <k8s/network> theName theEndpoint theNode (attrValues theNodes) theNetwork)
            (import <k8s/system>  theDeployment)
            (import <k8s/multus-cni>)
        ])
    )
) theNodes
