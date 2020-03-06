theCluster:

with import <nixpkgs/lib> ;

let isLB     = n: elem "loadbalancer" n.roles;
    isMaster = n: elem "master"       n.roles && ! isLB n;

    theName = theCluster.name or "kubernetes";

    theHype = theCluster.hypervisor or "virtualbox"; # or libvirtd
    isVBox  = s: s == "virtualbox";

    theNetwork = theCluster.network;

    theDeployment = theNode: resources: foldl recursiveUpdate { # default
        "${theHype}" = {
            headless   = true;
            memorySize = 2048;
            vcpu       = 2;
        };
    } [
        (theNode.deployment or {}) {
            targetEnv = theHype;
            "${theHype}".networks = (if isVBox theHype then [ { type = "nat"; } ] else []) ++ [
                resources."${theHype}Networks".network
            ];
        }
    ];

    theResources = {
        resources."${theHype}Networks".network = { resources, ...}: {
            type = if isVBox theHype then "hostonly" else "nat";
            cidrBlock = theNetwork.subnet;
            staticIPs = mapAttrs' (_: theNode: nameValuePair theNode.address resources.machines."${theNode.name}") theNodes;
        };
    };

    theNodes = mapAttrs (k: n: n // {
        name = k;
        nix  = if isLB n
               then <k8s/node/loadbalancer>
               else
                   if isMaster n
                   then <k8s/node/master>
                   else <k8s/node/worker> ;
    }) (filterAttrs (k: _: ! (elem k [ "name" "network" "hypervisor" ])) theCluster);

    theMasterNodes = filterAttrs (_: isMaster) theNodes;
    theLBNodes     = filterAttrs (_: isLB    ) theNodes;
    theEndpoint    = (head (attrValues (if theLBNodes != {} then theLBNodes else theMasterNodes))).address;
in
theResources // mapAttrs (_: theNode:
    (usingArgs@{ pkgs, config, lib, options, nodes, resources, ... }:
        lib.mkMerge (map (f: f usingArgs) (
            [
                (import theNode.nix   theName theEndpoint theNode (attrValues theMasterNodes))
                (import <k8s/network> theName theEndpoint theNode (attrValues theNodes) theNetwork)
                (import <k8s/system>  (theDeployment theNode resources))
            ] ++ (map (p: import "${<k8s-addons>}/${p}") (attrNames (builtins.readDir <k8s-addons>)))
        ))
    )
) theNodes
