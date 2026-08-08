{ config, inputs, ...} :
let
  # cryptid-specific

  version                   = "0.1.0-20260620";

  persist-partition-label   = "PERSIST";
  path-mount-persist        = "/persist";
  vault-name                = ".VAULT";
  path-vault-file           = "${path-mount-persist}/${vault-name}";
  path-mount-vault          = "/vault";

  vault-fs                  = "FAT";
  vault-size                = "300K";
  vault-hasher              = "sha512";
  vault-crypto              = "AES-Twofish";
  vault-pim                 = "0"; # use defaults

  pgp-expiry-in-months      = "13"; # one month buffer for annual extension
  pgp-rootkey-type          = "eddsa";
  pgp-rootkey-curve         = "ed25519";
  pgp-preferences           = "SHA512 AES256 ZLIB BZIP2 ZIP Uncompressed";
  pgp-sign-algorithm        = "ed25519";
  pgp-encrypt-algorithm     = "cv25519";

  yubi-retries-pin          = "5"; # signing, decryption, authentication
  yubi-retries-puk          = "5"; # the unblock pin, to reset user pin retry counter
  yubi-retries-admin        = "5"; # changing pins, setting retries, etc.
  yubi-touch-policy         = "on";
  yubi-pass-policy          = "once";
  yubi-age-pass-policy      = "once"; # never / once / always
  yubi-age-touch-policy     = "always"; # never / always / cached
  yubi-age-piv-slot         = "1";
  yubi-stock-pgp-pin        = "123456"; # "stock" pins from the factory
  yubi-stock-pgp-admin      = "12345678";
  yubi-stock-piv-pin        = yubi-stock-pgp-pin;
  yubi-stock-piv-puk        = yubi-stock-pgp-admin;
  yubi-stock-piv-mgt        = "010203040506070801020304050607080102030405060708";
  # TODO(crypt): age: switch back to AES192 PIV management key, pending https://github.com/str4d/age-plugin-yubikey/issues/92
  yubi-piv-management-alg   = "TDES"; # TDES|AES128|AES192|AES256  -- blocked by https://github.com/str4d/age-plugin-yubikey/issues/92

  path-firsttimeflag        = "/tmp/first-time-init";
  path-log-expectScript     = "./expectScript.log";

  pathv-yubicodes           = "${path-mount-vault}/yubicodes/yubicodes.env";
  pathv-pgp-private         = "${path-mount-vault}/pgp/pgp.key.asc";
  pathv-pgp-public          = "${path-mount-persist}/pgp-cert/pgp.certificate.asc";
  pathv-pgp-revoke          = "${path-mount-persist}/pgp-revoke/pgp.revocation.asc";
  pathv-ssh-public          = "${path-mount-persist}/sk-public/ssh_sk.pub";
  pathv-ssh-stub            = "${path-mount-persist}/sk-stub/ssh_sk";
  pathv-age-public          = "${path-mount-persist}/sk-public/age_sk.pub";
  pathv-age-stub            = "${path-mount-persist}/sk-stub/age_sk";
  pathv-merged-pubs-ssh     = "${path-mount-persist}/merged-ssh/authorized_keys";
  pathv-merged-pubs-age     = "${path-mount-persist}/merged-age/recipients.txt";
  emergency-label-ssh       = "cryptid-breakglass-ssh";
  emergency-label-age       = "cryptid-breakglass-age";
  emergency-filename        = name: "breakglass-${name}";
  emergency-filename-ssh    = emergency-filename "ssh";
  pathv-emerg-ssh-private   = "${path-mount-vault}/breakglass/${emergency-filename-ssh}";
  pathv-emerg-ssh-public    = "${path-mount-persist}/breakglass/${emergency-filename-ssh}.pub";
  emergency-filename-age    = emergency-filename "age";
  pathv-emerg-age-private   = "${path-mount-vault}/breakglass/${emergency-filename-age}";
  pathv-emerg-age-public    = "${path-mount-persist}/breakglass/${emergency-filename-age}.pub";

  mkdirs = [
    "${path-mount-persist}/merged-age"
    "${path-mount-persist}/merged-ssh"
    "${path-mount-persist}/breakglass"
    "${path-mount-persist}/sk-public"
    "${path-mount-persist}/sk-stub"
    "${path-mount-persist}/pgp-cert"
    "${path-mount-persist}/pgp-revoke"
    "${path-mount-vault}/pgp"
    "${path-mount-vault}/breakglass"
    "${path-mount-vault}/yubicodes"
  ];

  /*

  Persistent folder hierarchy
  Vault is an encrypted container.
  All files are versioned with a timestamp extension `<>`
  `sk-*` contents can be generated from the yubikey, but captured for convenience.

  ```
  vault/
    | pgp/
    |  | pgp-key.asc.<>
    | breakglass/
    |  | breakglass-ssh.<>
    |  | breakglass-age.<>
    | yubicodes/
    |  | yubicodes.env.<>

  merged-age/
    | recipients.txt.<>

  merged-ssh/
    | authorized_keys.<>

  breakglass/
    | breakglass-ssh.pub.<>
    | breakglass-age.pub.<>

  sk-public/
    | age_sk.pub.<>
    | ssh_sk.pub.<>

  sk-stub/
    | age_sk.<>
    | ssh_sk.<>

  pgp-cert/
    | pgp.certificate.asc.<>

  pgp-revoke/
    | pgp.revocation.asc.<>
  ```
  */

  env = {
    keyid = "KEYID";
    name = "USER_NAME";
    email = "USER_EMAIL";
    vaultpass = "VAULTPASS";
    yubi = {
      serial = "YUBI_SERIAL";
      fido.pin = "YUBI_FIDO_PIN";
      piv = {
        pin = "YUBI_PIV_PIN";
        puk = "YUBI_PIV_PUK";
      };
      pgp = {
        pin  = "YUBI_PGP_PIN";
        reset = "YUBI_PGP_RESET";
        admin = "YUBI_PGP_ADMIN";
      };
    };
  };

in
{
  # Something between here and 8c50a710ddca43d7a530fb805ad55bde8d0141c5 breaks mounting the btrfs partition... Too lazy to bisect.
  # TODO(workaround): occassionally check if cryptid nixpkgs is fixed
  nucleus.inputs.cryptid-nixpkgs.url = "nixpkgs/4c1018dae018162ec878d42fec712642d214fdfa";

  /**
    Bootable installer ISO (~1.5GB) intended for offline management of cryptographic identities; not intended for system installation. Provides various commandline tools for working with pgp, yubikeys, and veracrypt containers.
  */
  host.cryptid = {
    description = "Offline cryptographic identity management ISO.";
    primaryUser = "user";
    stateVersion = "26.05";
    nixpkgs = inputs.cryptid-nixpkgs;

    modules = [
      ({config, pkgs, lib, ...} :
  let
    username = config.hostIdentity.primaryUser;

    bash-ask-confirm-pass = var: str: ''
      if [[ -z "''$${var}" ]]; then
        while true; do
          read -rsp "Enter ${str}: " pass1
          echo
          read -rsp "Confirm ${str}: " pass2
          echo
          if [[ "$pass1" == "$pass2" ]]; then
            export ${var}="$pass1"
            break
          else
            echo "Inputs don't match. Please try again, or Ctrl+C to exit."
          fi
        done
      fi
    '';

    bash-make-gnupg-home = ''
      #https://github.com/Mic92/dotfiles/blob/ed0ac1af816a7ebb7c5d4f040b77fa88e3ec1c79/nixos/images/yubikey-image.nix
      export GNUPGHOME=/run/user/$(id -u)/gnupghome
      if [ ! -d "$GNUPGHOME" ]; then
        mkdir "$GNUPGHOME"
        chmod 700 "$GNUPGHOME"
      fi
      # workaround: ssh-keygen uses ccid killing device requiring a replug
      sudo echo "disable-ccid" > "$GNUPGHOME/scdaemon.conf"
    '';

    bash-get-keyid = ''
      if [[ -z "${"$" + env.keyid}" ]]; then
        export ${env.keyid}=$(gpg --list-secret-keys --keyid-format long --with-colons | awk -F: '/^fpr/{print $10; exit}')
        [[ -z "${"$" + env.keyid}" ]] && { echo "ERROR: failed to find KEYID"; return 1; }
      fi
    '';

    bash-get-yubiserial = ''
      mapfile -t serials < <( ykman list --serials | sed '/^[[:space:]]*$/d' )
      if [[ ''${#serials[@]} -eq 0 ]]; then
          echo "Error: No YubiKeys detected." >&2
          return 1
      fi
      if [[ ''${#serials[@]} -ne 1 ]]; then
          echo "Error: Expected only one YubiKey to be inserted." >&2
          printf 'Detected serials:\n%s\n' "''${serials[@]}" >&2
          return 1
      fi
      ${env.yubi.serial}=''${serials[0]}
      if [[ ! ${"$" + env.yubi.serial} =~ ^[0-9]+$ ]]; then
          echo "Error: Invalid serial number: ${"$" + env.yubi.serial}" >&2
          return 1
      fi
    '';

    # are these overkill? maybe... but decreases verbosity and makes the scripts more reliable.
    expect-error-cases = ''eof { puts "Error: unexpected EOF"; exit 3 } timeout { puts "Error: timeout"; exit 2 }'';
    expect-default-spawn = ''if {\$spawn eq ""} { set spawn \$::spawn_id }'';
    expect-header = ''
      set default_timeout_value 5
      set timeout \$default_timeout_value
      proc safe_expect { pattern {spawn ""} } {
        ${expect-default-spawn}
        # need to avoid {} to allow pattern string interp
        expect -i \$spawn \$pattern {} ${expect-error-cases}
      }

      proc safe_send { text {spawn ""} } {
        ${expect-default-spawn}
        send -i \$spawn -- "\$text\r"
      }

      proc safe_expect_end {{spawn ""}} {
        ${expect-default-spawn}
        expect -i \$spawn eof {} timeout { puts "Error: timeout while expecting EOF."; exit 2 }
      }

      proc oi { pattern text {spawn ""} } {
        ${expect-default-spawn}
        safe_expect \$pattern \$spawn
        safe_send \$text \$spawn
      }
    '';
    expect-gpgeditkey = ''
      # returns the number of 'ssb' subkeys listed by gpg
      proc count_subkeys {{spawn ""}} {
        ${expect-default-spawn}
        oi "gpg>" "list" \$spawn
        set subkey_count 0
        expect -i \$spawn -re {(?m)^ssb} { incr subkey_count; exp_continue } -notransfer "gpg>" {} ${expect-error-cases}
        if {\$subkey_count == 0} { puts "Error: No subkeys found"; exit 1 }
        if {\$subkey_count % 2 != 0} { puts "Error: Number of subkeys must be divisible by 2"; exit 1 }
        return \$subkey_count
      }
    '';

    scriptCatalog = import (inputs.self + /data/cryptid) {
      inherit lib pkgs;
      context = {
        inherit
          bash-ask-confirm-pass
          bash-get-keyid
          bash-get-yubiserial
          bash-make-gnupg-home
          emergency-label-age
          emergency-label-ssh
          env
          expect-default-spawn
          expect-error-cases
          expect-gpgeditkey
          expect-header
          mkdirs
          path-firsttimeflag
          path-log-expectScript
          path-mount-persist
          path-mount-vault
          path-vault-file
          pathv-age-public
          pathv-age-stub
          pathv-emerg-age-private
          pathv-emerg-age-public
          pathv-emerg-ssh-private
          pathv-emerg-ssh-public
          pathv-merged-pubs-age
          pathv-merged-pubs-ssh
          pathv-pgp-private
          pathv-pgp-public
          pathv-pgp-revoke
          pathv-ssh-public
          pathv-ssh-stub
          pathv-yubicodes
          pgp-encrypt-algorithm
          pgp-expiry-in-months
          pgp-preferences
          pgp-rootkey-curve
          pgp-rootkey-type
          pgp-sign-algorithm
          username
          vault-crypto
          vault-fs
          vault-hasher
          vault-pim
          vault-size
          version
          yubi-age-pass-policy
          yubi-age-piv-slot
          yubi-age-touch-policy
          yubi-pass-policy
          yubi-piv-management-alg
          yubi-retries-admin
          yubi-retries-pin
          yubi-retries-puk
          yubi-stock-pgp-admin
          yubi-stock-pgp-pin
          yubi-stock-piv-mgt
          yubi-stock-piv-pin
          yubi-stock-piv-puk
          yubi-touch-policy
          ;
      };
    };

  in {

    # platform
    imports = with inputs.self.modules.nixos; [
      isolive
      airgap
      # not using cryptos from flake; micromanage dependencies
    ];
    image.fileName = lib.mkForce "${config.hostIdentity.name}-${pkgs.stdenv.hostPlatform.system}";
    boot = {
      tmp.cleanOnBoot = true;
      supportedFilesystems = { btrfs = true; };
      kernel.sysctl = {"kernel.unprivileged_bpf_disabled" = 1;};
      loader.grub = {
        enable                   = true;
        device                   = "nodev";
        efiSupport               = true;
        efiInstallAsRemovable    = true;
      };
    };
    swapDevices = [];
    fileSystems = lib.mkOverride 59 (
      config.lib.isoFileSystems // {
      "${path-mount-persist}" = {
        device = "/dev/disk/by-label/${persist-partition-label}";
        fsType = "btrfs";
        neededForBoot = true;
        options = [ "defaults" "compress=zstd" "noatime" ];
      };}
    );

    # user
    services.getty.autologinUser = lib.mkForce username;
    users.users."${username}" = {
      isNormalUser      = true;
      description       = "admin";
      extraGroups       = [ "wheel" "systemd-journal" ];
      # This image uses console autologin and passwordless sudo; keep password
      # authentication explicitly locked instead of publishing a placeholder.
      hashedPassword = "!";
    };
    security.sudo.wheelNeedsPassword = lib.mkForce false;

    # services
    services.pcscd.enable = true;

    # TODO(quality): these scripts use gpg; if I was doing it again I'd use sq/sequoia-pgp + oct/OpenPGP-card-tools
    programs.gnupg.agent.enable = true;
    programs.gnupg.agent.pinentryPackage = pkgs.pinentry-tty;
    hardware.gpgSmartcards.enable = true;

    environment.etc."issue".text = scriptCatalog.helpText;
    environment.interactiveShellInit = bash-make-gnupg-home;

    environment.systemPackages = with pkgs; [
      expect
      rusty-diceware
      paperkey
      qrencode
      kpcli
      zbar
      veracrypt
      gnupg
      pcsc-tools
      yubikey-manager
      age
      age-plugin-yubikey
    ] ++ scriptCatalog.packages;
  })
    ];
  };

  /**
  Comes with a helper script to destructively provision a bootable USB flashdrive formatted with an additional btrfs partition for manually managed persistance. The rationale for this is a backup strategy which bundles data with the tools needed to use it. Encrypted containers can be made on the persistant partition and the entire drive can be cloned for redundancy.

  > [!CAUTION]
  > ```
  > nix run .#mkbootable-cryptid -- /dev/sdX
  > ```

  Tip: use can use the following command to quickly enumerate removable blockdevices alongside their sizes.
  ```
  nix run nixpkgs#nushell -- -c "lsblk --json | from json | get blockdevices | where rm == true | select name size"
  ```
  */
  flake.apps.x86_64-linux.mkbootable-cryptid = {
    meta.description = "Write the cryptid ISO and persistent partition to a block device.";
    program =
      let
        name = "cryptid";
        iso = config.flake.nixosConfigurations.${name}.config.system.build.isoImage;
        pkgs = config.host.${name}.nixpkgs.legacyPackages.${config.host.${name}.system};
      in
      toString (config.flake.lib.mkIsoWriter {
        inherit name pkgs iso;
        postWrite = ''
          printf "\nAppending partition to %s ...\n" "$DEV"
          echo ", ,L" | sudo sfdisk --append --quiet "$DEV"
          sleep 1
          udevadm settle
          sleep 2

          LAST_PART=$(sudo partx -rgo NR "$DEV" | tail -1)
          printf "\nFormatting %s%s as btrfs...\n" "$DEV" "$LAST_PART"
          sudo ${pkgs.btrfs-progs}/bin/mkfs.btrfs -L "${persist-partition-label}" -f -m dup -d dup -M -q "''${DEV}''${LAST_PART}"
        '';
      });
  };
}
