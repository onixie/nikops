let
    nixpkgs = builtins.fetchTarball https://github.com/NixOS/nixpkgs/archive/20.03-beta.tar.gz;
    # {
    #     url = "https://github.com/NixOS/nixpkgs/archive/19.09.tar.gz";
    #     sha256 = "0mhqhq21y5vrr1f30qd2bvydv4bbbslvyzclhw0kdxmkgg3z4c92";
    # };

    nixops          = builtins.fetchGit {
        url = https://github.com/onixie/nixops;
        ref = "expose-privateipv4-to-machine-definition";
        rev = "042ba74d43232e2f0792b25e7d20db9470215961";
    };
    nixops-vbox     = builtins.fetchGit https://github.com/onixie/nixops-vbox;
    nixops-libvirtd = builtins.fetchGit {
        url = https://github.com/onixie/nixops-libvirtd;
        ref = "network-resource-support";
        rev = "992b06a699faa2ae51f82ecab826db3ce5ec9887";
    };

    pkgs = import nixpkgs { config = {}; };
    lib  = pkgs.lib;

    addSrc = lib.concatMapStringsSep ":" (n: "k8s/${n}=${./src/. + "/${n}.nix"}");

    curDir=with builtins; toPath (getEnv "PWD")

    dplDir=".deploy";

    pkiDir="${dplDir}/pki";

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
    export NIXOPS_STATE="${dplDir}/state.nixops"
    export NIX_PATH="${lib.concatStringsSep ":"
        [
            "nixpkgs=${nixpkgs}"

            (addSrc [ "cluster" "network" "node/master" "node/worker" "node/loadbalancer" "system" ])

            (if builtins.pathExists (curDir + "proxy.nix")
             then "k8s/proxy=./proxy.nix"
             else "k8s/proxy=")

            (if builtins.pathExists (curDir + "hypervisor.nix")
             then "k8s/hypervisor=./hypervisor.nix"
             else "k8s/hypervisor=")

            "k8s-res=${./. + "/resources"}"

            "k8s-addons=${./src/. + "/addons"}"

            "k8s-pki=${pkiDir}"

            "."
        ]}"

    mkdir -p ${dplDir}
    mkdir -p ${pkiDir}
  '';
}
