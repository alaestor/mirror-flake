{ self, ... }: let
  module-name = "ssh-host";

  # maybe these should be from some "paths" options...
  secrets-path = "/etc/secrets";
  secrets-path-initrd = "${secrets-path}/initrd";

in
{

  /**
    Automates some opinionated configuration for providing remote ssh access. If more granular control is desired, you should avoid using this.

    When configuring hosts for pre-boot ssh (`initrd.enable`):
    - an ED25516 ssh key must be present at `initrd.HostKeyPath` to be passed along by `initrd.secrets`. Don't use your system host key (`HostKeyPath`).
    - the system will probably need to configure `systemd.network`
    - may need to set `boot.initrd.availableKernelModules` for network hardware availability (use `lspci -v | grep -iA8 'network\|ethernet'` for that).

    > [!CAUTION]
    > The initrd ssh host key is stored unencrypted in `/boot/secrets/`. If an attacker was to gain access to it (particularly through physical access) they could impersonate the server and intercept your LUKS passphrase.
  */

  flake.modules.nixos."${module-name}" = {config, lib, ...}: let cfg = config."${module-name}"; in with lib;
  {
    options."${module-name}" = {
      initrd = {

        enable = mkOption {
          type= types.bool;
          default = false;
          description = "Permits ssh access during boot. May be needed for entering LUKS passphrases.";
        };

        port = mkOption {
          type = types.int;
          default = 2222;
          description = "An ssh port for the pre-boot ssh session. Must not conflict with the post-boot ssh port.";
        };

        hostKeyPath = mkOption {
          type = types.path;
          default = "${secrets-path-initrd}/ssh_host_ed25519_key";
          description = ''
            The absolute filepath of the automatically generated ed25519 initrd host key.
            It must be in an unencrypted partition that's mounted during boot.
          '';
        };

        forceLuksPrompt = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Force the SSH session to only allow LUKS passphrase entry via
            `systemd-tty-ask-password-agent`. Alternatively, you can do this from the
            client-side: `ssh -tt <user>@<ip> <command>` or by configuring an
            initrd-specific sshconfig `Host` with a `RemoteCommand` field.

            NOTE: Forcing the LUKS passphrase prompt limits remote debugging opportunities.
          '';
        };

      };

      comment = mkOption {
        type = types.str;
        default = "generated host key (${config.networking.hostName})";
        defaultText = literalExpression "\"generated host key - \${config.networking.hostName}\"";
        description = ''
          the comment for the hostkey. If `initrd.enable` is true,
          its key will also have this comment suffixed with '_initrd'.
        '';
      };

      sftp-enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enables sftp and adds the `aes128-ctr` to the ciphers list for faster transfers at the cost of security.";
      };

      hostKeyPath = mkOption {
        type = types.path;
        default = "${secrets-path}/ssh/ssh_host_ed25519_key";
        description = "The absolute filepath of where to store the automatically generated ed25519 host key.";
      };

      allowUsers = mkOption {
        type = with types; nullOr (listOf str);
        default = null;
        description = "Forwarded to the OpenSSH NixOS module. See {manpage}`sshd_config(5)` for details.";
      };

      addAuthorizedKeysToUsers = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically add `${module-name}.authorizedKeys` to the users listed in `${module-name}.allowedUsers`.";
      };

      authorizedKeys = mkOption {
        type = types.listOf types.singleLineStr;
        default = self.data.vars.sshAuthorizedKeys;
        defaultText = literalExpression ''self.data.vars.sshAuthorizedKeys;'';
        description = ''
          If `${module-name}.addAuthorizedKeysToUsers` is true, the keys listed here
          will be added to users configured in `${module-name}.AllowUsers`, and
          the initrd root if `${module-name}.initrd.enable` is true.
        '';
      };
    };

    config = {
      # Add authorized keys to each allowed user (if configured)
      users.users = lib.mkIf (cfg.addAuthorizedKeysToUsers && cfg.allowUsers != null) (
        lib.genAttrs cfg.allowUsers (_: {
          openssh.authorizedKeys.keys = cfg.authorizedKeys;
        })
      );

      # OpenSSH and enable fail2ban
      services = {
        fail2ban.enable = true;
        openssh = {
          enable               = true;
          openFirewall         = true;
          hostKeys             = [ {comment = cfg.comment; type = "ed25519"; path = cfg.hostKeyPath; } ];
          sftpServerExecutable = mkIf cfg.sftp-enable "internal-sftp";
          sftpFlags            = mkIf cfg.sftp-enable [ "-l INFO" ];
          settings             = {
            PermitRootLogin              = mkDefault "no"; # ISO installer overrides to "yes"
            PasswordAuthentication       = false;
            KbdInteractiveAuthentication = false;
            AllowUsers                   = cfg.allowUsers;
            X11Forwarding                = false;
            UseDns                       = false;
            LogLevel                     = "VERBOSE"; # also gets set by fail2ban
            Compression                  = "no";
            # Requires OpenSSH ≥ 9.0 (NixOS 24.05+ ships ≥ 9.x). Post-quantum ML-KEM (mlkem768x25519) mitigates store-now-decrypt-later attacks.
            Ciphers                      = [ "chacha20-poly1305@openssh.com" "aes256-gcm@openssh.com" ] ++ lib.optionals cfg.sftp-enable [ "aes128-ctr" ];
            KexAlgorithms                = [ "mlkem768x25519-sha256" "curve25519-sha256" "curve25519-sha256@libssh.org" ];
            Macs                         = [ "hmac-sha2-256-etm@openssh.com" "hmac-sha2-512-etm@openssh.com" "umac-128-etm@openssh.com" ];
          };
          extraConfig          = ''
            PerSourceMaxStartups 20
            PerSourceNetBlockSize 32:128
          '';
        };
      };

      # Initrd host keys may be provisioned during installation, so do not
      # require the target path to exist on the machine evaluating this config.
      assertions = map (a: mkIf cfg.initrd.enable a) [
        {
          assertion = cfg.hostKeyPath != cfg.initrd.hostKeyPath;
          message = ''
            ${module-name}.initrd.hostKeyPath and ${module-name}.hostKeyPath must be different.
            The `initrd.HostKeyPath` is be stored unencrypted in the initrd image.
            Don't use your system main key for this!
          '';
        }
      ];

      boot.initrd = mkIf cfg.initrd.enable {
      network = {
        enable = true;
        ssh = {
          enable = true;
          port = cfg.initrd.port;
          hostKeys = [ cfg.initrd.hostKeyPath ];
          authorizedKeys = mkForce cfg.authorizedKeys;
          extraConfig = mkIf cfg.initrd.forceLuksPrompt ''
            ForceCommand systemd-tty-ask-password-agent
          '';
        };
      };

        # Networking config for the initrd (systemd-networkd, required since 26.05)
        systemd.network.enable = cfg.initrd.enable;
      };
    };
  };
}
