/**
  Local Forgejo software-forge configuration.

  Forgejo expects to be reached via shared Caddy reverse proxy (`serve.caddy`),
  which terminates TLS itself. Git-over-SSH is served through
  the host's existing OpenSSH daemon (the upstream module's default).
*/
{
  flake.modules.nixos.serve-forgejo =
    { config, lib, options, pkgs, ... }:
    let
      cfg = config.serve.forgejo;
      hasServicesMountpoint = lib.hasAttrByPath [ "nas" "services" "mountpoint" ] options;
      hasSshHostAllowUsers = lib.hasAttrByPath [ "ssh-host" "allowUsers" ] options;
    in
    {
      options.serve.forgejo = {
        enable = lib.mkEnableOption "the local Forgejo software-forge service";

        domain = lib.mkOption {
          type = lib.types.nonEmptyStr;
          description = "Public domain Forgejo is served under.";
        };

        address = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Local Forgejo HTTP listener address.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 3000;
          description = "Local Forgejo HTTP listener port.";
        };

        sshPort = lib.mkOption {
          type = lib.types.port;
          default = 22;
          description = ''
            SSH port advertised in clone URLs. Git-over-SSH is served
            through the host's existing OpenSSH daemon (always on its
            real port, e.g. `ssh-host.port`), so only change this when a
            different *external* port is forwarded to it (e.g. NAT
            port-forwarding a non-standard public port to the host's
            internal port 22).
          '';
        };

        dataRoot = lib.mkOption {
          type = lib.types.str;
          default = if hasServicesMountpoint then "${config.nas.services.mountpoint}/forgejo" else "/mnt/Services/forgejo";
          defaultText = lib.literalExpression ''
            if NAS module present
            then "''${config.nas.services.mountpoint}/forgejo"
            else "/mnt/Services/forgejo"
          '';
          description = "Root directory holding Forgejo's state and LFS data.";
        };
      };

      config = lib.mkIf cfg.enable {
        services.forgejo = {
          enable = true;
          stateDir = "${cfg.dataRoot}/state";

          lfs = {
            enable = true;
            contentDir = "${cfg.dataRoot}/lfs";
          };

          settings = {
            DEFAULT = {
              APP_NAME = "「EOT」";
              RUN_MODE = "prod"; # default but make explicit
            };

            server = {
              DOMAIN = cfg.domain;
              ROOT_URL = "https://${cfg.domain}/";
              HTTP_ADDR = cfg.address;
              HTTP_PORT = cfg.port;
              PROTOCOL = "http";
              SSH_PORT = cfg.sshPort;
              LANDING_PAGE = "explore";
            };

            # Caddy will use TLS so session cookies should still be marked secure.
            session.COOKIE_SECURE = true;

            service = {
              # admin-provisioned only; no self-service sign-up.
              DISABLE_REGISTRATION = true;
              REGISTER_EMAIL_CONFIRM = false;
              # licenses to surface
              PREFERRED_LICENSES = "AGPL-3.0, MIT, Apache-2.0";
            };

            repository = {
              # allow creating repos via authenticated `git push`
              ENABLE_PUSH_CREATE_USER = true;
              ENABLE_PUSH_CREATE_ORG = true;
              DEFAULT_PRIVATE = "private";
              DEFAULT_PUSH_CREATE_PRIVATE = true;
            };

            security = {
              # Be explicit about never using the web installer.
              INSTALL_LOCK = true;
              # trust X-Forwarded-For client IPs for accurate audit/fail2ban-relevant logging.
              REVERSE_PROXY_TRUSTED_PROXIES = "127.0.0.1/32";
              REVERSE_PROXY_LIMIT = 1;
            };

            # No external OpenID provider is wired up; keep the sign-in
            # surface limited to local accounts.
            openid.ENABLE_OPENID_SIGNIN = false;

            # Automate routine housekeeping (repo GC, deleted-repo archive cleanup, etc.)
            cron.ENABLED = true;
            "cron.git_gc_repos".ENABLED = true;
          };
        };

        # TODO(serve): maybe this workaround and option defaults should be lanser config?
        # dataRoot may live on a lazily-mounted network share (see `nas.services`).
        # Upstream's `systemd.tmpfiles.rules` run early in boot before mount without
        # any explicit dependency, and errors since the path doesn't exist yet
        systemd.services = lib.genAttrs [
          "systemd-tmpfiles-setup"
          "forgejo-secrets"
          "forgejo"
        ] (_: { unitConfig.RequiresMountsFor = [ cfg.dataRoot ]; });

        # expects REVERSE_PROXY_TRUSTED_PROXIES and and log MODE console.
        services.fail2ban.jails.forgejo = {
          filter = {
            Definition = {
              journalmatch = "_SYSTEMD_UNIT=forgejo.service";
              # fmting needed due to ini generator failing indentation
              failregex = lib.concatStringsSep "\n  " [
                "^.*Failed authentication attempt for .* from <HOST>$"
                "^.*invalid credentials from <HOST>$"
                "^.*Attempted access of unknown user .* from <HOST>$"
              ];
              ignoreregex = "";
            };
          };
          settings = {
            enabled = true;
            backend = "systemd";
            maxretry = 10;
            findtime = "10m";
            bantime = "1h";
          };
        };

        # Git-over-SSH authenticates against the `forgejo` system user's
        # own forced-command authorized_keys written/managed by Forgejo
        # itself; wire directly into sshd's AllowUsers: Don't use ssh-host.
        services.openssh.settings.AllowUsers = lib.mkIf hasSshHostAllowUsers [ "forgejo" ];

        # TODO(serve): maybe this workaround and option defaults should be lanser config?
        # WORKAROUND(permenant): because forgejo's authorized_keys file may live on zfs, ssh complains about its file permissions and refuses to read.
        environment.etc."ssh/authorized_keys_command_forgejo" = {
          mode = "0755";
          text = ''
            #!/bin/sh
            exec ${pkgs.coreutils}/bin/cat ${cfg.dataRoot}/state/.ssh/authorized_keys
          '';
        };
        services.openssh.extraConfig = lib.mkAfter ''
          Match User forgejo
            AuthorizedKeysCommand /etc/ssh/authorized_keys_command_forgejo
            AuthorizedKeysCommandUser root
          Match all
        '';
      };
    };
}
