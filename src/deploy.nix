theNode: inNetworkWith: otherNodes: usingArgs@{ pkgs, config, lib, options, nodes, ... }:
lib.mkMerge (map (f: f usingArgs)
  [
    (import <k8s/system>)
    (import theNode) (inNetworkWith otherNodes)
    (import <k8s/multus-cni>)
  ]
)
