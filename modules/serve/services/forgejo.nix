/**
  Local Forgejo software-forge service without public ingress policy.

  Forgejo is only ever reached through the shared Caddy reverse proxy
  (`serve.caddy`), which terminates TLS itself. Forgejo never needs its own
  certificate, so there's nothing to share with the `forgejo` service user.
  Git-over-SSH is served through the host's existing OpenSSH daemon (the
  upstream module's default), so no extra port needs to be opened either.
*/
{
  flake.modules.nixos.serve-forgejo =
    { config, lib, options, ... }:
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
            server = {
              DOMAIN = cfg.domain;
              ROOT_URL = "https://${cfg.domain}/";
              HTTP_ADDR = cfg.address;
              HTTP_PORT = cfg.port;
              PROTOCOL = "http";
              SSH_PORT = cfg.sshPort;
            };

            # Forgejo itself only ever speaks plain HTTP to Caddy, but the
            # public-facing URL is HTTPS (Caddy terminates TLS), so session
            # cookies should still be marked secure.
            session.COOKIE_SECURE = true;

            # This instance is admin-provisioned only (see `forgejo admin
            # user create`); no self-service sign-up.
            service = {
              DISABLE_REGISTRATION = true;
              REGISTER_EMAIL_CONFIRM = false;
            };

            # Never re-run/expose the web installer (even though NixOS
            # already renders app.ini fully). Caddy is the only thing that
            # can reach Forgejo (loopback), so also trust its
            # X-Forwarded-For for real client IPs -- needed for accurate
            # audit/fail2ban-relevant logging.
            security = {
              INSTALL_LOCK = true;
              REVERSE_PROXY_TRUSTED_PROXIES = "127.0.0.1/32";
              REVERSE_PROXY_LIMIT = 1;
            };

            # No external OpenID provider is wired up; keep the sign-in
            # surface limited to local accounts.
            openid.ENABLE_OPENID_SIGNIN = false;

            # Keep routine housekeeping (repo GC, deleted-repo archive
            # cleanup, etc.) actually running instead of relying on manual
            # maintenance.
            cron.ENABLED = true;
            "cron.git_gc_repos".ENABLED = true;
          };
        };

        # dataRoot may live on a lazily-mounted network share (see
        # `nas.services`). The upstream module's `systemd.tmpfiles.rules`
        # (which create `stateDir`/`customDir`) run as part of the global
        # `systemd-tmpfiles-setup.service`, early in boot and before the
        # network is up, so without an explicit dependency the mount may
        # not be triggered in time and directory creation silently fails.
        # `forgejo-secrets.service` then fails hard with a NAMESPACE error
        # because `customDir` doesn't exist yet. RequiresMountsFor forces
        # systemd to mount `dataRoot` first wherever it's needed.
        systemd.services = lib.genAttrs [
          "systemd-tmpfiles-setup"
          "forgejo-secrets"
          "forgejo"
        ] (_: { unitConfig.RequiresMountsFor = [ cfg.dataRoot ]; });

        # Forgejo doesn't rate-limit its own login endpoints. It logs
        # failed authentication attempts to stdout (captured in the
        # journal, since the default log MODE is console), tagged with
        # the real client IP now that REVERSE_PROXY_TRUSTED_PROXIES is
        # configured above. Ban repeat offenders the same way ssh-host
        # already does for sshd.
        services.fail2ban.jails.forgejo = {
          filter = {
            Definition = {
              journalmatch = "_SYSTEMD_UNIT=forgejo.service";
              # `pkgs.formats.ini`'s generator emits each line of a
              # multi-line Nix string flush-left, which fail2ban's INI
              # parser reads as unindented, unrelated lines rather than a
              # continuation of `failregex` -- hence the "parsing errors"
              # fail2ban reported. INI continuation lines must be
              # indented, so build the value with an explicit leading
              # two-space indent on every line after the first.
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
        # own forced-command authorized_keys (written/managed by Forgejo
        # itself), but sshd's AllowUsers defaults to only the host's
        # primary user, which rejects `forgejo` before key lookup ever
        # runs. Contribute directly to the underlying sshd setting rather
        # than `ssh-host.allowUsers`: that option's own module also grants
        # every listed user the full administrative SSH key set with a
        # *plain, unrestricted* shell -- which would silently bypass
        # Forgejo's per-account command restriction for anyone holding an
        # admin key.
        services.openssh.settings.AllowUsers = lib.mkIf hasSshHostAllowUsers [ "forgejo" ];
      };
    };
}
