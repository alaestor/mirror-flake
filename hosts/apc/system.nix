{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  username = config.hostIdentity.primaryUser;
  home = "/home/${username}";
  agents = inputs.self.lib.agents;
in
{
  age.identityPaths = [ config.ssh-host.hostKeyPath ];

  # Which harnesses this host's agent VM carries state for. Named here
  # rather than in the module because this host is what decides which
  # harness features are attached in the first place (`modules/host/apc.nix`
  # attaches `ai-coding` through the workstation environment); the VM module
  # is forbidden from naming a state directory itself, and a standalone Home
  # Manager attachment is not evaluated during `nixos-rebuild`, so it cannot
  # contribute one either.
  agent-vm = {
    enable = true;
    stateDirs = agents.stateDirsFor home [
      "claude"
      "codex"
      "headroom"
      "serena"
    ];
    guestEnvironment = agents.environmentFor home;
  };

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
    allowed-users = [
      "@wheel"
      # The agent VM's nix daemon channel connects as this account. It is
      # allowed to talk to the daemon and deliberately not trusted by it, so
      # the guest can build and add store paths but cannot tell the daemon to
      # trust content from anywhere else. See modules/mechanisms/agents/.
      config.agent-vm.nixProxyUser
    ];
  };

  nas = {
    server = "172.16.0.2"; # TODO(lan): nas ip
    cauldron.enable = true;
    vault.enable = true;
    pocket.enable = true;
  };

  programs.virt-manager.enable = true;

  steam-gaming = {
    enable = true;
    remotePlay.openFirewall = true;
    suppressCrashReports = true;
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

  systemd.oomd.enable = false; # TODO: oomd + earlyoomkiller module (or just global?)

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
