theDeployment: { pkgs, lib, ... }:

with lib;
{
    deployment  = theDeployment;
    swapDevices = mkForce [ ]; # https://github.com/NixOS/nixops/issues/1062
    programs.bash = {

        shellAliases = {
            s = "systemctl";
            j = "journalctl";
        };

        interactiveShellInit = concatStringsSep "\n" [
            ". ${pkgs.systemd}/share/bash-completion/completions/systemctl && complete -F _systemctl s"
        ];
    };
}
