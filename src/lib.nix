with import <nixpkgs> {};
rec {
  fromYAML = yaml: {
    apiVersion = "v1";
    kind = "List";
    items = builtins.fromJSON (
      builtins.readFile (
        runCommand "fromYAML" { buildInputs = [ jq yq ]; } ''
            ${pkgs.yq}/bin/yq -sM . ${
              if !lib.pathIsDirectory yaml
              then yaml
              else "${yaml}/*"
            } > $out
        ''
      )
    );
  };

  asAddon = vs: with lib;
  if isList vs
  then map asAddon vs
  else if !isAttrs vs
  then vs
  else let vs' = mapAttrs (ns: asAddon) vs; in if !(vs ? "apiVersion" && vs ? "kind")
  then vs'
  else recursiveUpdate vs' {
    metadata.labels = {
      "kubernetes.io/cluster-service"   = "true";
      "addonmanager.kubernetes.io/mode" = "Reconcile";
    };
  };

  inNamespace = nms: vs: with lib;
  if isList vs
  then map (inNamespace nms) vs
  else if !isAttrs vs
  then vs
  else let vs' = mapAttrs (ns: inNamespace nms) vs; in if !(vs ? "apiVersion" && vs ? "kind")
  then vs'
  else recursiveUpdate vs' {
    metadata.namespace = nms;
  };

  permitAddonManagerForClusterwise = purpose: { verbs ? [ "*" ], apiGroups ? [ "*" ], resources ? ["*"], resourceNames ? null } :
  # code segment copied from
  # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/cluster/kubernetes/addon-manager.nix#L96-L125
  let
    name = "system:kube-addon-manager";
  in
  {
    apiVersion = "v1";
    kind = "List";
    items = [
      {
        apiVersion = "rbac.authorization.k8s.io/v1";
        kind = "ClusterRole";
        metadata = {
          name = "${name}:${purpose}";
        };
        rules = [ {
          inherit verbs apiGroups resources resourceNames;
        }];
      }
      {
        apiVersion = "rbac.authorization.k8s.io/v1";
        kind = "ClusterRoleBinding";
        metadata = {
          name = "${name}:${purpose}";
        };
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "${name}:${purpose}";
        };
        subjects = [{
          kind = "User";
          inherit name;
        }];
      }
    ];
  };

  permitAddonManagerInNamespace = ns:
  # code segment copied from
  # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/cluster/kubernetes/addon-manager.nix#L96-L125
  let
    name = "system:kube-addon-manager";
    namespace = ns;
  in
  {
    apiVersion = "v1";
    kind = "List";
    items = [
      {
        apiVersion = "v1";
        kind = "Namespace";
        metadata.name = namespace;
        spec = {};
      }
      {
        apiVersion = "rbac.authorization.k8s.io/v1";
        kind = "Role";
        metadata = {
          inherit name namespace;
        };
        rules = [{
          apiGroups = ["*"];
          resources = ["*"];
          verbs = ["*"];
        }];
      }
      {
        apiVersion = "rbac.authorization.k8s.io/v1";
        kind = "RoleBinding";
        metadata = {
          inherit name namespace;
        };
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "Role";
          inherit name;
        };
        subjects = [{
          apiGroup = "rbac.authorization.k8s.io";
          kind = "User";
          inherit name;
        }];
      }
    ];
  };
}
