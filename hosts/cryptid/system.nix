{ config, lib, pkgs, ... }:
let
  username = config.hostIdentity.primaryUser;
in
{
  image.fileName = lib.mkForce "${config.hostIdentity.name}-${pkgs.stdenv.hostPlatform.system}";
  boot = {
    tmp.cleanOnBoot = true;
    supportedFilesystems.btrfs = true;
    kernel.sysctl = { "kernel.unprivileged_bpf_disabled" = 1; };
    loader.grub = {
      enable = true;
      device = "nodev";
      efiSupport = true;
      efiInstallAsRemovable = true;
    };
  };
  swapDevices = [ ];

  services.getty.autologinUser = lib.mkForce username;
  users.users.${username} = {
    isNormalUser = true;
    description = "admin";
    extraGroups = [ "wheel" "systemd-journal" ];
    hashedPassword = "!";
  };
  security.sudo.wheelNeedsPassword = lib.mkForce false;

  services.pcscd.enable = true;
  programs.gnupg.agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-tty;
  };
  hardware.gpgSmartcards.enable = true;

  environment.systemPackages = with pkgs; [
    expect
    rusty-diceware
    paperkey
    qrencode
    kpcli
    zbar
    veracrypt
    gnupg
    pcsc-tools
    yubikey-manager
    age
    age-plugin-yubikey
  ];
}
