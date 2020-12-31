with import <nixpkgs> {};
{
  fromYAML = yaml: builtins.fromJSON (
    builtins.readFile (
      runCommand "fromYAML" {} "cat '${yaml}' | ${pkgs.yaml2json}/bin/yaml2json > $out"
    )
  );
  asAddon = with lib; mapAttrsRecursiveCond
  (as: as ? "metadata" && as ? "apiVersion" && as ? "kind")
  (ps: vs:
  if !(last ps == "metadata" && isAttrs vs)
  then vs
  else mergeAttrs vs {
    labels = {
      "kubernetes.io/cluster-service"   = "true";
      "addonmanager.kubernetes.io/mode" = "Reconcile";
    };
  });
}
