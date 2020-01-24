deployCfg: { lib, config, ... }:

with lib;

deployCfg // {
    swapDevices = mkForce [ ]; # https://github.com/NixOS/nixops/issues/1062
}
