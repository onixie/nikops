args@{ config, lib, ... }:

let profile = import <nixpkgs/nixos/modules/profiles/qemu-guest.nix> args;
in
lib.mkMerge [ profile {

  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "ehci_pci" "ahci" "sd_mod" "sr_mod" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "${config.boot.loader.grub.device}1";
      fsType = "ext4";
    };

  swapDevices = [ ];

  nix.maxJobs = lib.mkDefault 16;
}]
