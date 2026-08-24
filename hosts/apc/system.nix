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
  # noblesse offloads its builds here; see __reference/remote-build-trust.md.
  remoteBuildUser = "nixremote";
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
      # Remote builders must also be allowed to reach the daemon at all;
      # being trusted does not imply being allowed.
      remoteBuildUser
    ];
    # The remote-build protocol hands the builder a derivation in-band rather
    # than realising one already in its store, so the daemon cannot re-derive
    # the output paths and must take the client's word for them. It refuses to
    # do that for input-addressed derivations (i.e. all of nixpkgs) unless the
    # account is trusted. This is why the grant exists and why it cannot be
    # avoided while nixpkgs is input-addressed.
    #
    # Trust here is store-poisoning power, hence root-equivalent, hence it goes
    # to a dedicated non-interactive account rather than `user`: `user` is what
    # every interactive session and every agent process on this host runs as,
    # and `sudo` is meant to remain a real gate for them.
    #
    # `root` is contributed by the nix module itself and merges with this.
    trusted-users = [ remoteBuildUser ];
  };

  # Reached only by noblesse's client key, and only to serve its store: the
  # forced command means possession of that key buys the store protocol rather
  # than a shell. Deliberately *not* routed through `ssh-host.authorizedKeys`,
  # which would attach the administrative key set to this account unrestricted
  # and hand out an unsudoed shell as a trusted user.
  #
  # NOTE(coupling): `builders = ssh://...` on noblesse speaks the legacy store
  # protocol (`nix-store --serve`). Switching that URL to `ssh-ng://` changes
  # the wire protocol to `nix-daemon --stdio` and this command must change with
  # it, or every offloaded build hangs.
  users.users.${remoteBuildUser} = {
    isSystemUser = true;
    group = remoteBuildUser;
    home = "/var/empty";
    # sshd executes the forced command through the account's login shell, so
    # this cannot be `nologin`.
    shell = pkgs.bashInteractive;
    description = "Trusted remote-build account for noblesse";
    openssh.authorizedKeys.keys = [
      ("command=\"${config.nix.package}/bin/nix-store --serve --write\","
        + "restrict "
        + inputs.self.data.vars.sshClientPublicKeys.noblesse)
    ];
  };
  users.groups.${remoteBuildUser} = { };

  # `ssh-host.allowUsers` drives the module's `AllowUsers`; this merges with it
  # rather than replacing it, so the account is reachable without joining the
  # set that receives the administrative keys.
  services.openssh.settings.AllowUsers = [ remoteBuildUser ];

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

  # Baseline security/service hardening (sudo-rs, apparmor, disabled
  # avahi/printing broadcast, etc.) comes from the `server-hardening` feature
  # module this host imports; only apc-specific overrides live here.
  security.lockKernelModules = false;

  services.ratbagd = {
    enable = true;
    package = pkgs.libratbag;
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

  # KDE has a notification daemon to actually surface these; the defaults
  # (zram at 30%, kill below 10% free) are what this host ran before
  # memory-manager existed.
  memory-manager.earlyoom.notifications = true;

}
