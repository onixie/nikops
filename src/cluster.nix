theCluster:

with import <nixpkgs/lib> ;

let theName = theCluster.name or "kubernetes";

    theNetwork = theCluster.network;
    isManaged = n: !(n ? managed) || n.managed != false;

    theNodes = mapAttrs (k: n: n // {
        name = k;
        nix  = if isLB n
               then <k8s/node/loadbalancer>
               else
                   if isMaster n
                   then <k8s/node/master>
                   else <k8s/node/worker> ;
    }) (filterAttrs (k: _: ! (elem k [ "name" "network" "hypervisor" ])) theCluster);
    isLB     = n: elem "loadbalancer" n.roles;
    isMaster = n: elem "master"       n.roles && ! isLB n;

    theMasterNodes = filterAttrs (_: isMaster) theNodes;
    theLBNodes     = filterAttrs (_: isLB    ) theNodes;

    theEndpoint    = (head (attrValues (if theLBNodes != {} then theLBNodes else theMasterNodes))).address;

    theHypervisor = theCluster.hypervisor or "virtualbox"; # or libvirtd
    isVirtualBox  = s: s == "virtualbox";

    theDeployment = theNode: resources:
        let
            d = foldl recursiveUpdate { # default
                targetEnv = theHypervisor;
                "${theHypervisor}" = {
                    headless   = true;
                    memorySize = 2048;
                    vcpu       = 2;
                    networks   = let net1 = if isManaged theNetwork then [ resources."${theHypervisor}Networks".network ] else [];
                                     net2 = if isVirtualBox theHypervisor then [ { type = "nat"; } ] else [];
                                 in net1++net2;
                };
            } [
                { "${theHypervisor}" = (import <k8s/hypervisor>)."${theHypervisor}" or {}; }
                { "${theHypervisor}" = theNode."${theHypervisor}" or {}; }
            ];

            isLocal = d: isVirtualBox theHypervisor || (!(d."${theHypervisor}" ? URI)) || d."${theHypervisor}".URI == "qemu:///system";
        in
          if isManaged theNetwork && !(isLocal d)
          then throw "Managed network is only supported for local deployment!"
          else d;


    theResources = if isManaged theNetwork then {
        resources."${theHypervisor}Networks".network = { resources, ...}: {
            type = if isVirtualBox theHypervisor then "hostonly" else "nat";
            cidrBlock = theNetwork.subnet;
            staticIPs = mapAttrs' (_: theNode: nameValuePair theNode.address resources.machines."${theNode.name}") theNodes;
        } // filterAttrs (k: v: k == "URI") ((import <k8s/hypervisor>)."${theHypervisor}" or {});
    } else {};

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
