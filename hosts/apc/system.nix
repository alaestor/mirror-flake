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
    # Same two roots `claude-code.nix`'s bubblewrap sandbox has always
    # allowed (`sandboxWritableRoots`) — Phase 8 (`cc`/`ccs` onto
    # `agent-vm-session`) needs the guest to be able to see whatever the
    # caller's `$PWD` is, and unlike bubblewrap's per-invocation bind mounts,
    # virtiofs shares are fixed at boot, so this has to name the trees up
    # front rather than pick them dynamically. Deliberately not "wherever
    # the caller happens to be" — see the Phase 8 handoff for why arbitrary
    # per-session mounts were ruled out.
    projectRoots = [
      "${home}/Projects"
      "/mnt/Vault/.dotfiles/flake"
    ];
    stateDirs = agents.stateDirsFor home [
      "claude"
      "codex"
      "headroom"
      "serena"
    ];
    guestEnvironment = agents.environmentFor home;
    # `agent-vm-session` (Phase 7) ssh's from this host into its own guest,
    # so the identity it needs is apc's own SSH client identity — the same
    # one `vm-smoke-test.nix` authorizes, and for the same reason. Without
    # this the guest has zero authorized keys and every login is refused
    # with "Permission denied (publickey,keyboard-interactive)" no matter
    # how correct everything else is.
    authorizedKeys = [ inputs.self.data.vars.sshClientPublicKeys.apc ];
    # 10 minutes rather than the module default of 2: `agent-vm-stop` exists
    # for the case where the guest should come down right away, so the
    # automatic linger is free to favor "outlives a short gap between
    # sessions" over "tears down promptly" without costing anything on the
    # other axis.
    lifecycle.lingerSeconds = 10 * 60;
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
