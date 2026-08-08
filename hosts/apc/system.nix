{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  username = config.hostIdentity.primaryUser;
in
{
  age.identityPaths = [ config.ssh-host.hostKeyPath ];

  crypto-yubikey.administrativeStubs.enable = true;

  serve.nix-cache.enable = true;

  ssh-host.authorizedKeys = [ inputs.self.data.vars.sshClientPublicKeys.noblesse ];

  environment = {
    sessionVariables.NIXOS_OZONE_WL = "1";
    systemPackages = with pkgs; [
      pinentry-tty
      wl-clipboard-rs
      xkill
      nfs-utils
      p7zip
      unrar
      unar
      lzip
      mozlz4a
      kdePackages.kgpg
      kdePackages.ksystemlog
      kdePackages.partitionmanager
      kdePackages.xdg-desktop-portal-kde
    ];
  };

  fonts.packages = builtins.filter lib.attrsets.isDerivation (builtins.attrValues pkgs.nerd-fonts);

  # TODO(apc): yeet nix.settings (is @wheel even needed?)
  nix.settings = {
    auto-optimise-store = true;
    download-buffer-size = 524288000 * 2; # TODO(global): download-buffer-size
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    allowed-users = [ "@wheel" ];
  };

  nas = {
    server = "172.16.0.2"; # TODO(lan): nas ip
    cauldron.enable = true;
    vault.enable = true;
    pocket.enable = true;
  };

  programs = {
    steam = {
      enable = true;
      remotePlay.openFirewall = true;
    };
    virt-manager.enable = true;
  };

  security = {
    lockKernelModules = false;
    protectKernelImage = true;
    forcePageTableIsolation = true;
    virtualisation.flushL1DataCache = "always";
    sudo.enable = false;
    sudo-rs = {
      enable = true;
      package = pkgs.sudo-rs;
      execWheelOnly = true;
    };
    apparmor = {
      enable = true;
      killUnconfinedConfinables = true;
    };
  };

  services = {
    earlyoom = {
      enable = true;
      enableNotifications = true;
    };
    ratbagd = {
      enable = true;
      package = pkgs.libratbag;
    };
    avahi.enable = lib.mkForce false;
    printing = {
      browsed.enable = lib.mkForce false;
      browsing = lib.mkForce false;
    };
  };

  systemd = {
    oomd.enable = false; # TODO: oomd + earlyoomkiller module (or just global?)

    # TODO(apc): make a gaming aspect and move this into a steam module
    user.services.preventSteamDumps = {
      description = "Symlink Steam crash reports to /dev/null";
      script = "ln -s /dev/null /tmp/dumps";
      wantedBy = [ "multi-user.target" ];
    };
  };

  users.users.${username} = {
    isNormalUser = true;
    description = username;
    extraGroups = [
      "networkmanager"
      "wheel"
      "kvm"
      "ydotool"
      "input"
      "uinput"
    ];
  };

  virtualisation = {
    libvirtd.enable = true;
    podman = {
      enable = true;
      dockerCompat = true;
    };
  };

  xdg.portal.enable = true;
  zramSwap = {
    enable = true;
    memoryPercent = 30;
  };

}
