{ pkgs, ... }: 
{
  boot.loader.grub.enable = true;
  boot.loader.grub.version = 2;
  boot.loader.grub.efiSupport = false;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.systemd-boot.enable = false;

  users.users.root.hashedPassword="$6$SaxxBGzTLaoaA$AKG9DzDlfZETlZiWkRmcNfJkjbv/hHRCmzs6ToQdJ4O724.T9lgtKrzl7soZ.oMHuwF8Y/FjnjpdagR9MPEI20";
  users.mutableUsers = false;

  services.openssh = {
    enable = true;
    permitRootLogin = "yes";
  };

  environment = {
    systemPackages = with pkgs;[ vim emacs kubectl git ];
    variables = { EDITOR = "emacs"; };
  };

  system.stateVersion = "unstable";
}
