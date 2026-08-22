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
      };
    };
}
