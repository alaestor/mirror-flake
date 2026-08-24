/**
  # ssh-host

  Exports `flake.modules.nixos.ssh-host` and
  `flake.modules.nixOnDroid.ssh-host`. Both module classes expose the common
  `ssh-host` interface; only NixOS additionally exposes `ssh-host.initrd`.

  Importing either module enables an SSH server. `allowUsers` selects the
  accounts to which login keys are attached. `allow-administrative-access`
  authorizes the complete administrative primary/recovery key set and defaults
  to true. `authorizedKeys` is an empty-by-default, additive list for any other
  login identities. Host public keys are never login identities and must not be
  added to either set.

  Each platform generates or consumes one persistent Ed25519 host key at
  `hostKeyPath`. The default filename is `ssh_host_ed25519_key_<hostname>`,
  where the hostname is normalized to lowercase. NixOS owns service and
  firewall lifecycle. Nix-on-droid instead installs explicit start/stop
  commands because Android provides no compatible service manager.

  When NixOS initrd SSH is enabled, its root login receives the same additive
  administrative and explicit authorization set. Its host key is always
  distinct from the system host key.
*/
{ self, ... }: let
  module-name = "ssh-host";
  commonOptions =
    { config, lib, port ? 22, hostKeyDirectory ? "/etc/ssh" }:
    with lib;
    let
      hostName = toLower config.hostIdentity.name;
    in
    {
      comment = mkOption {
        type = types.str;
        default = "generated host key (${config.hostIdentity.name})";
        defaultText = literalExpression ''"generated host key (\${config.hostIdentity.name})"'';
        description = "The comment stored in the generated host public key.";
      };

      port = mkOption {
        type = types.port;
        default = port;
        description = "TCP port on which the SSH daemon listens.";
      };

      sftp-enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enables SFTP and adds `aes128-ctr` for faster transfers at the cost of security.";
      };

      hostKeyPath = mkOption {
        type = types.path;
        default = "${hostKeyDirectory}/ssh_host_ed25519_key_${hostName}";
        description = "Absolute path at which the generated Ed25519 host key is stored.";
      };

      allowUsers = mkOption {
        type = with types; nullOr (listOf str);
        default = [ config.hostIdentity.primaryUser ];
        defaultText = literalExpression ''[ config.hostIdentity.primaryUser ]'';
        description = "Users allowed to log in. A null value does not add an `AllowUsers` restriction.";
      };

      allow-administrative-access = mkOption {
        type = types.bool;
        default = true;
        description = "Authorize all configured administrative SSH identities for the selected users.";
      };

      authorizedKeys = mkOption {
        type = types.listOf types.singleLineStr;
        default = [ ];
        description = "Additional public keys authorized for users selected by `ssh-host.allowUsers`.";
      };
    };
in
{
  /**
    Automates some opinionated configuration for providing remote ssh access. If more granular control is desired, you should avoid using this.

    When configuring hosts for pre-boot ssh (`initrd.enable`):
    - an ED25519 ssh key must be present at `initrd.hostKeyPath` to be passed along by `initrd.secrets`. Don't use your system host key (`hostKeyPath`).
    - the system will probably need to configure `systemd.network`
    - may need to set `boot.initrd.availableKernelModules` for network hardware availability (use `lspci -v | grep -iA8 'network\|ethernet'` for that).

    > [!CAUTION]
    > The initrd copy of this SSH host key is stored unencrypted in bootloader-accessible material. If an attacker gains physical access to it, they could impersonate the server and intercept your LUKS passphrase.
  */

  flake.modules.nixos."${module-name}" = {config, lib, ...}: let cfg = config."${module-name}"; in with lib;
  {
    options."${module-name}" = commonOptions { inherit config lib; } // {
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
          default = "/etc/secrets/initrd/ssh_host_ed25519_key_${toLower config.hostIdentity.name}_initrd";
          description = ''
            The absolute filepath of the automatically generated ed25519 initrd host key.
            It is staged by the deployer on the encrypted root filesystem, then
            copied into bootloader-accessible initrd secret material.
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

    };

    config = {
      # Add authorized keys to each allowed user (if configured)
      users.users = lib.mkIf (cfg.allowUsers != null) (
        lib.genAttrs cfg.allowUsers (_: {
          openssh.authorizedKeys.keys =
            lib.optionals cfg.allow-administrative-access self.data.vars.sshAdminKeys
            ++ cfg.authorizedKeys;
        })
      );

      # OpenSSH and enable fail2ban
      services = {
        fail2ban.enable = true;
        openssh = {
          enable               = true;
          openFirewall         = true;
          ports                = [ cfg.port ];
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
            The `initrd.hostKeyPath` is stored unencrypted in the initrd image.
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
          authorizedKeys = mkForce (
            lib.optionals cfg.allow-administrative-access self.data.vars.sshAdminKeys
            ++ cfg.authorizedKeys
          );
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

  /**
    Configures an opinionated OpenSSH host for nix-on-droid using the same
    `ssh-host` options as NixOS. It installs `ssh-host-start` and
    `ssh-host-stop`; Android does not provide systemd or another reliable
    nix-on-droid service lifecycle.
  */
  flake.modules.nixOnDroid."${module-name}" =
    { config, lib, pkgs, ... }:
    let
      cfg = config.${module-name};
      stateDirectory = "${config.user.home}/.local/state/ssh-host";
      pidFile = "${stateDirectory}/sshd.pid";
      authorizedKeysFile = pkgs.writeText "ssh-host-authorized-keys" (
        lib.concatMapStringsSep "\n" (key: key) (
          lib.optionals cfg.allow-administrative-access self.data.vars.sshAdminKeys
          ++ cfg.authorizedKeys
        ) + "\n"
      );
      allowUsers = lib.optionalString (cfg.allowUsers != null) ''
        AllowUsers ${lib.concatStringsSep " " cfg.allowUsers}
      '';
      authorizedKeys = lib.optionalString (cfg.allowUsers != null) ''
        AuthorizedKeysFile ${authorizedKeysFile}
      '';
      sftp = lib.optionalString cfg.sftp-enable ''
        Subsystem sftp internal-sftp
      '';
      sshdConfig = pkgs.writeText "ssh-host-sshd-config" ''
        Port ${toString cfg.port}
        HostKey ${cfg.hostKeyPath}
        PidFile ${pidFile}
        PasswordAuthentication no
        KbdInteractiveAuthentication no
        PermitRootLogin no
        X11Forwarding no
        UseDNS no
        LogLevel VERBOSE
        Compression no
        Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com${lib.optionalString cfg.sftp-enable ",aes128-ctr"}
        KexAlgorithms mlkem768x25519-sha256,curve25519-sha256,curve25519-sha256@libssh.org
        MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com
        PerSourceMaxStartups 20
        PerSourceNetBlockSize 32:128
        ${allowUsers}
        ${authorizedKeys}
        ${sftp}
      '';
      start = pkgs.writeShellScriptBin "ssh-host-start" ''
        set -eu
        mkdir -p ${lib.escapeShellArg stateDirectory}
        exec ${pkgs.openssh}/bin/sshd -f ${sshdConfig} -E ${lib.escapeShellArg "${stateDirectory}/sshd.log"}
      '';
      stop = pkgs.writeShellScriptBin "ssh-host-stop" ''
        set -eu
        if [ ! -s ${lib.escapeShellArg pidFile} ]; then
          echo "ssh-host is not running (no PID file)" >&2
          exit 1
        fi
        kill "$(cat ${lib.escapeShellArg pidFile})"
      '';
    in
    {
      options.${module-name} = commonOptions {
        inherit config lib;
        port = 8022;
        hostKeyDirectory = "${config.user.home}/.local/state/ssh-host";
      };

      config = {
        assertions = [
          {
            assertion = cfg.allowUsers == null || lib.all (user: user == config.user.userName) cfg.allowUsers;
            message = "nix-on-droid ssh-host.allowUsers may only contain `${config.user.userName}`.";
          }
        ];

        build.activation.ssh-host-key = ''
          if [ ! -s ${lib.escapeShellArg (toString cfg.hostKeyPath)} ]; then
            $DRY_RUN_CMD mkdir $VERBOSE_ARG --parents ${lib.escapeShellArg (builtins.dirOf (toString cfg.hostKeyPath))}
            $DRY_RUN_CMD ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 \
              -C ${lib.escapeShellArg cfg.comment} -N "" -f ${lib.escapeShellArg (toString cfg.hostKeyPath)}
          fi
        '';

        environment.packages = [ pkgs.openssh start stop ];
      };
    };
}
