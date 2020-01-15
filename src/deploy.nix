theNode: inNetworkAs: theRole: theOtherNodes: usingArgs@{ pkgs, config, lib, options, nodes, ... }:
lib.mkMerge (map (f: f usingArgs)
  [
    (import <k8s/system>)
    (import theRole) (inNetworkAs theNode theOtherNodes)
    (import <k8s/multus-cni>)
  ]
)
