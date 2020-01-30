let
    nixpkgs = builtins.fetchTarball {
        url    = "https://nixos.org/channels/nixos-unstable/nixexprs.tar.xz";
        sha256 = "189770mh3bcdvnkpnabdyxz026w5cr9v03rn3ix1rw6ci4i8l83w";
    };

    pkgs = import nixpkgs { config = {}; };
    lib  = pkgs.lib;

    addSrc = lib.concatMapStringsSep ":" (n: "k8s/${n}=${./src/. + "/${n}.nix"}");
in

pkgs.mkShell {
    buildInputs = with pkgs; [ nixops cfssl ];

    shellHook = ''
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
