theNode: inNetworkAs: theRole: theOtherNodes: deployCfg: usingArgs@{ pkgs, config, lib, options, nodes, ... }:
lib.mkMerge (map (f: f usingArgs)
    [
        (import theRole theNode) (inNetworkAs theNode theOtherNodes)
        (import <k8s/system> deployCfg)
        (import <k8s/multus-cni>)
    ]
)
