/**
  Authenticated, read-only media downloads with search and folder ZIPs.
  A private filesystem root exposes only named shares and the Nix store.
  A service-owned AppArmor profile limits reads, executable mappings, and
  execution to the daemon and its fixed account-validation dependencies.
  Accounts come from a required runtime environment file, normally agenix;
  missing, anonymous, plaintext, or writable account rules fail startup.
*/
{ self, ... }:
{
  flake.modules.nixos.serve-dufs =
    { config, lib, pkgs, ... }:
    let
      cfg = config.serve.dufs;
      root = "/run/dufs-root";
      absolutePath = lib.types.addCheck lib.types.str (lib.hasPrefix "/");
      validateAuth = pkgs.writeShellApplication {
        name = "dufs-validate-auth";
        text = self.data.read "serve/dufs/validate-auth.sh";
      };
      libraryRules = packages: pkgs.apparmorRulesFromClosure {
        name = "dufs-libraries";
        # No blanket execution grant, including for libexec helpers.
        baseRules = [ "$path/lib/** mr" "$path/lib64/** mr" ];
      } packages;
    in
    {
      options.serve.dufs = {
        enable = lib.mkEnableOption "authenticated read-only media downloads";
        address = lib.mkOption {
          type = lib.types.enum [ "127.0.0.1" "::1" ];
          default = "127.0.0.1";
          description = "Loopback listener behind the public reverse proxy.";
        };
        port = lib.mkOption {
          type = lib.types.ints.between 1024 65535;
          default = 8087;
          description = "Private HTTP listener port.";
        };
        shares = lib.mkOption {
          type = lib.types.attrsOf absolutePath;
          default = { };
          example = { Films = "/srv/media/films"; };
          description = "Public folder names mapped to read-only host directories. All accounts see the same shares.";
        };
        authFile = lib.mkOption {
          type = lib.types.nullOr absolutePath;
          default = null;
          description = ''
            Required runtime EnvironmentFile defining DUFS_AUTH. Each account
            must use a SHA-512 crypt hash and @/:ro; separate accounts with |.
            Keep it out of the Nix store, for example through agenix.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        security.apparmor = {
          enable = true;
          policies.serve-dufs.profile = ''
            profile serve-dufs flags=(chroot_relative) {
              ${lib.getExe config.services.dufs.package} rix,
              # The fixed ExecStartPre guard needs Bash. It inherits this same
              # policy, including the absence of general write permissions.
              ${lib.getExe validateAuth} rix,
              ${lib.getExe pkgs.bash} rix,
              ${builtins.storeDir}/** r,
              include "${libraryRules [ config.services.dufs.package pkgs.bash ]}"
              owner /proc/[0-9]*/{maps,cgroup} r,
              /media/ r,
              ${lib.concatMapStringsSep "\n" (name: ''
                /media/${name}/ r,
                /media/${name}/** r,
              '') (builtins.attrNames cfg.shares)}
              /dev/null rw,
              /dev/tty rw,
              /dev/urandom r,
              network inet stream,
              network inet6 stream,
              signal (receive) peer=unconfined,
              signal (send, receive) peer=serve-dufs,
            }
          '';
        };

        assertions = [
          {
            assertion = cfg.authFile != null;
            message = "serve.dufs requires a runtime authFile; anonymous serving is not supported.";
          }
          {
            assertion = cfg.shares != { } && builtins.all
              (name: builtins.match "[a-zA-Z0-9][a-zA-Z0-9_-]*" name != null)
              (builtins.attrNames cfg.shares);
            message = "serve.dufs requires named shares using letters, digits, underscores, or hyphens.";
          }
        ];

        services.dufs = {
          enable = true;
          bindAddresses = [ cfg.address ];
          inherit (cfg) port;
          servePath = "/media";
          environmentFile = cfg.authFile;
          settings = {
            auth-method = "basic";
            allow-all = false;
            allow-upload = false;
            allow-delete = false;
            allow-search = true;
            allow-archive = true;
            allow-symlink = false;
            allow-hash = false;
            enable-cors = false;
            compress = "none";
          };
        };

        # PID 1 creates bind destinations before applying ProtectSystem.
        # Root ownership prevents this account from changing the host-side root.
        systemd.tmpfiles.rules = [ "d ${root} 0755 root root -" ];
        systemd.services.dufs = {
          requires = [ "apparmor.service" ];
          after = [ "apparmor.service" ];
          # Refuse startup on a kernel without AppArmor instead of silently
          # starting unconfined. AppArmorProfile also requires a loaded profile.
          unitConfig.AssertSecurity = "apparmor";
          unitConfig.RequiresMountsFor = builtins.attrValues cfg.shares;
          serviceConfig = {
            AppArmorProfile = "serve-dufs";
            RootDirectory = root;
            BindReadOnlyPaths = [ builtins.storeDir ] ++ lib.mapAttrsToList
              (name: source: "${source}:/media/${name}") cfg.shares;
            ExecStartPre = lib.getExe validateAuth;
            ProtectHome = true;
            # '+' addresses the private root, not the host's /run.
            ReadOnlyPaths = [ "+/run" ];
            # Upstream grants write access to servePath. This service is
            # deliberately download-only, including at the filesystem layer.
            ReadWritePaths = lib.mkForce [ ];
            SystemCallArchitectures = "native";
            SystemCallFilter = [ "@system-service" ];
            IPAddressDeny = "any";
            IPAddressAllow = "localhost";
          };
        };
      };
    };
}
