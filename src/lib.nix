with import <nixpkgs> {};
{
  fromYAML = yaml: builtins.fromJSON (
    builtins.readFile (
      runCommand "fromYAML" {} "cat '${yaml}' | ${pkgs.yaml2json}/bin/yaml2json > $out"
    )
  );
}
