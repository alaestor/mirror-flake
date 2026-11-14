{ inputs, tailnet, lan }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  username = config.hostIdentity.primaryUser;
  secretPath = inputs.self.secrets.path;
in
{
  age = {
    identityPaths = [ config.ssh-host.hostKeyPath ];
    secrets = {
      lanser-torrenting-wireguard-config = {
        file = secretPath "vpn_P2PUSCA560.conf.age";
        mode = "0400";
      };
      lanser-headplane-cookie-secret = {
        file = secretPath "headplane_cookie-secret.age";
        mode = "0400";
      };
      lanser-dufs-auth = {
        file = secretPath "dufs-auth.env.age";
        mode = "0400";
      };
    };
  };

  # Public-facing host: passwordless autologin into LXQt is intentional here
  # (kiosk-style access to the media/torrent services this host runs).
  auto-login.user = username;

  environment.systemPackages = with pkgs; [
    git
    openssh
    pinentry-tty
    btop
    iftop
    ghostty
    tmux
    home-manager
    p7zip
    unrar
    unar
    mozlz4a
    chromium
  ];

  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    defaultEditor = true;
  };

  users.users.${username} = {
    isNormalUser = true;
    description = username;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  ssh-host = {
    allowUsers = [ username ];
    comment = "lanser-hostkey";
  };

  nas = {
    server = "192.168.2.200";
    vault = {
      enable = true;
      readonly = true;
    };
    pocket.enable = true;
    services.enable = true;
  };

  telemetry-server.enable = true;

  serve = {
    caddy = {
      enable = true;
      bindAddress = lan.reservations.lanser;
    };
    cinny.enable = true;
    dufs = {
      enable = true;
      authFile = config.age.secrets.lanser-dufs-auth.path;
      shares = {
        Anime = "${config.nas.vault.mountpoint}/Media/Anime";
        Movies = "${config.nas.vault.mountpoint}/Media/Movies";
        Music = "${config.nas.vault.mountpoint}/Media/Music/Library";
      };
      # TODO(ui): customize dufs css
    };
    forgejo = {
      enable = true;
      dataRoot = "${config.nas.services.mountpoint}/forgejo";
      # headplane (behind serve.headscale) defaults to 3000 too; avoid the
      # clash since this host runs both.
      port = 3001;
      # Router forwards external 38502 -> this host's real sshd (port 22,
      # via ssh-host), so git clone URLs advertise the port people can
      # actually reach from outside the LAN/tailnet.
      sshPort = 38502;
    };
    headscale = {
      enable = true;
      adminAllowedCIDRs = [ lan.cidr ];
      cookieSecretFile = config.age.secrets.lanser-headplane-cookie-secret.path;
    };
    jellyfin.enable = true;
    matrix.enable = true;
    static-site-0x04.enable = true;
    static-site-bokunopi.enable = true;
    torrenting = {
      enable = true;
      wireguardConfigFile = config.age.secrets.lanser-torrenting-wireguard-config.path;
    };
  };

  # Forgejo state is on the NAS. Stop its units before the share is detached.
  systemd.services = (lib.genAttrs [ "forgejo-secrets" "forgejo" ] (_: {
    after = [ "nas-detach.service" ];
  })) // {
    headplane = lib.mkIf config.serve.headscale.enable {
      after = [ "agenix.service" ];
      restartTriggers = [ (builtins.hashFile "sha256" (secretPath "headplane_cookie-secret.age")) ];
      # The administrative UI has no reason to inspect the host's NAS shares.
      serviceConfig.TemporaryFileSystem = [ "/mnt:ro" ];
    };
    dufs = lib.mkIf config.serve.dufs.enable {
      after = [ "agenix.service" "nas-detach.service" ];
      # EnvironmentFile is loaded on start, not on credential rotation.
      restartTriggers = [ (builtins.hashFile "sha256" (secretPath "dufs-auth.env.age")) ];
    };
    # Hide the NAS mount tree, then expose only each workload's data. Bind at
    # the original paths so Jellyfin's local alias symlinks continue to work.
    jellyfin = lib.mkIf config.serve.jellyfin.enable {
      serviceConfig = {
        TemporaryFileSystem = [ "/mnt:ro" ];
        BindReadOnlyPaths = [ config.serve.jellyfin.libraryBuilder.source ];
      };
    };
    qbittorrent = lib.mkIf config.serve.torrenting.enable {
      # Pocket is the torrent workspace, including inboxes and integrated data
      # still being seeded. Preserve per-torrent paths across that share.
      unitConfig.RequiresMountsFor = [ config.nas.pocket.mountpoint ];
      serviceConfig = {
        TemporaryFileSystem = [ "/mnt:ro" ];
        BindPaths = [ config.nas.pocket.mountpoint ];
        ReadWritePaths = [ config.nas.pocket.mountpoint ];
      };
    };
  };

  # sshd rejects the permissions on the NAS-backed authorized_keys file.
  # Keep this storage-specific workaround alongside the dataRoot selection.
  environment.etc."ssh/authorized_keys_command_forgejo" = {
    mode = "0755";
    text = ''
      #!/bin/sh
      exec ${pkgs.coreutils}/bin/cat ${config.services.forgejo.stateDir}/.ssh/authorized_keys
    '';
  };

  services = {
    # TODO(workaround): use stable Tuwunel until unstable supplies system AWS-LC; tracked in https://github.com/NixOS/nixpkgs/issues/570938
    matrix-tuwunel.package =
      inputs.stable-nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.matrix-tuwunel;

    openssh.extraConfig = lib.mkAfter ''
      Match User forgejo
        AuthorizedKeysCommand /etc/ssh/authorized_keys_command_forgejo
        AuthorizedKeysCommandUser root
      Match all
    '';

    headscale.settings = {
      dns = {
        magic_dns = true;
        base_domain = tailnet.dnsSuffix;
        override_local_dns = true;
        nameservers.global = [
          "1.1.1.1"
          "1.0.0.1"
        ];
      };
      trusted_proxies = [ "127.0.0.1/32" ];
    };
  };
}
