let
    nixpkgs = builtins.fetchTarball {
        url    = "https://nixos.org/channels/nixos-unstable/nixexprs.tar.xz";
        sha256 = "1ygvhl72mjwfgkag612q9b6nvh0k5dhdqsr1l84jmsjk001fqfa7";
    };

    nixops          = builtins.fetchGit https://github.com/onixie/nixops;
    nixops-vbox     = builtins.fetchGit https://github.com/onixie/nixops-vbox;
    nixops-libvirtd = builtins.fetchGit {
        url = https://github.com/onixie/nixops-libvirtd;
        ref = "network-resource-support";
    };

    pkgs = import nixpkgs { config = {}; };
    lib  = pkgs.lib;

    addSrc = lib.concatMapStringsSep ":" (n: "k8s/${n}=${./src/. + "/${n}.nix"}");
in

pkgs.mkShell {
    buildInputs = [
        (import "${nixops}/release.nix" {
            p = (p: [
                (p.callPackage "${nixops-vbox}/release.nix" {})
                (p.callPackage "${nixops-libvirtd}/release.nix" {})
            ]);
        }).build.x86_64-linux
        pkgs.cfssl
    ];

    shellHook = ''
    export NIXOPS_STATE="./.state.nixops"
    export NIX_PATH="${lib.concatStringsSep ":"
        [
            "nixpkgs=${nixpkgs}"

            (addSrc [ "cluster" "network" "node/master" "node/worker" "node/loadbalancer" "system" ])

            (if builtins.pathExists ./proxy.nix
             then "k8s/proxy=./proxy.nix"
             else "k8s/proxy=")

            (if builtins.pathExists ./deployment.nix
             then "k8s/deployment=./deployment.nix"
             else "k8s/deployment=")

            "k8s-res=./resources"

            "k8s-addons=${./src/. + "/addons"}"

            "."
        ]}"
  '';
}
