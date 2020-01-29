theDeployment: { lib, ... }:

with lib;
{
    deployment  = theDeployment;
    swapDevices = mkForce [ ]; # https://github.com/NixOS/nixops/issues/1062
}
