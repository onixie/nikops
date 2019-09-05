let
  nixpkgs = builtins.fetchTarball {
    url    = "https://nixos.org/channels/nixos-unstable/nixexprs.tar.xz";
    sha256 = "189770mh3bcdvnkpnabdyxz026w5cr9v03rn3ix1rw6ci4i8l83w";
  };

  pkgs = import nixpkgs { config = {}; };
  nm = pkgs.lib.concatMapStringsSep ":" (n: "k8s/${n}=${./src/. + "/${n}.nix"}");
in

pkgs.mkShell {
  buildInputs = [ pkgs.nixops ];

  shellHook = ''
    export NIX_PATH="nixpkgs=${nixpkgs}:${nm ["deploy" "system" "network" "master" "worker" "hardware" "multus-cni"]}:k8s-res=${./resources}:.";
  '';
}
