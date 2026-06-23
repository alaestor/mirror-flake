{ inputs, ...} :
let
  # normal host information

  system = "x86_64-linux";
  hostname = "cryptid";
  username = "user";

  # cryptid-specific

  version                   = "0.1.0-20260620";
  bootable                  = "mkbootable-${hostname}";

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

  # reusable text for scripts

  docstr = ''
    *************
    ** CRYPTID **              version ${version}
    *************

    Bootable Offline NixOS for cryptographic ID management

    Helper scripts

      ? ----------------- print this menu
      list-files -------- list contents of persist and vault
      list-pgp ---------- list most recent PGP keys
      list-age ---------- list most recent age identities
      list-ssh ---------- list most recent ssh identities
      list-yubicodes ---- list most recent YubiKey PINs
      load-secrets ------ load most recent PINs / passcodes
      print_keyid ------- print the first private PGP signature
      print_ykserial ---- print the YubiKey serial

    Lesser scripts: tool operation abstractions

      vault-init -------- initialize the persistent vault
      vault-open -------- open the persistent vault
      vault-cd ---------- change directory to vault mount
      vault-close ------- close the persistent vault
      gpg-clean --------- delete and recreate the gpg folder
      gpg-new-rootkey --- create a new root key
      gpg-new-subkeys --- create new sign and encrypt subkeys
      gpg-rev-subkeys --- revoke the newest two subkeys
      gpg-backup -------- export keys to vault
      gpg-restore ------- import keys from vault
      gpg-test ---------- verify root key
      ssh-emerg-make ---- create and backup emergency ssh key
      ssh-emerg-test ---- verify emergency ssh backup
      ssh-mergepubs ----- yubi+breakglass -> 'authorized_keys'
      age-emerg-make ---- create and backup emergency age key
      age-emerg-test ---- verify emergency age backup
      age-mergepubs ----- yubi+breakglass -> 'recipients.txt'
      yubi-reset -------- reset the YubiKey to factory defaults
      yubi-new-ssh ------ create a resident ssh key on the YubiKey
      yubi-new-age ------ create a resident age key on the YubiKey
      yubi-move-keys ---- move the two pgp subkeys to the YubiKey
      yubi-extend ------- extend all subkeys by ${pgp-expiry-in-months} months

    Greater scripts: workflow compositions

      first-time-init --- create vault, PGP, AGE, emergency keys
      init-yubikey ------ provision yubikey, create resident keys
      extend-subkeys ---- extend PGP subkeys
      rotate-subkeys ---- revoke PGP subkeys and generate new ones
      rotate-sshkeys ---- make new resident and breakglass ssh keys
      rotate-agekeys ---- make new resident and breakglass age keys
      rotate-all -------- rotate all keys (except pgp root identity)
      verify ------------ run all tests

    ______________________________________________________

    Persistent storage is mounted at: ${path-mount-persist}/
    The vault, once opened, will be mounted at: ${path-mount-vault}/
    ______________________________________________________

    'root' has an empty password. '${username}' password is 'pass'.

  '';
in
{
  # Something between here and 8c50a710ddca43d7a530fb805ad55bde8d0141c5 breaks mounting the btrfs partition... Too lazy to bisect.
  # TODO(workaround): occassionally check if cryptid nixpkgs is fixed
  flake-file.inputs.cryptid-nixpkgs.url = "nixpkgs/4c1018dae018162ec878d42fec712642d214fdfa";

  /**
    Bootable installer ISO (~1.5GB) intended for offline management of cryptographic identities; not intended for system installation. Provides various commandline tools for working with pgp, yubikeys, and veracrypt containers.
  */
  flake.nixosConfigurations = inputs.self.lib.mkNixos system hostname inputs.cryptid-nixpkgs;
  flake.modules.nixos.${hostname} =  {config, pkgs, lib, ...} :
  let
    mkScript = name: content: pkgs.writeShellScriptBin name ''
      printf "\n— ${name} —\n"
      set -eo pipefail
      # workaround: wrapper to allow 'return' because 'exit' is problematic when used with 'source'
      _impl() {
      ${content}
      }
      _impl "$@"
    '';

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

  in {

    # platform
    imports = with inputs.self.modules.nixos; [
      isolive
      airgap
      # not using cryptos from flake; micromanage dependencies
    ];
    networking.hostName = hostname;
    image.fileName = lib.mkForce "${hostname}-${pkgs.stdenv.hostPlatform.system}";
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
      hashedPassword    = "$y$j9T$Gv/KnS.l8oYx/wXkuipev0$WaGNfph3nVa/1kU1yXray/31rMk9z6CLUtibkLPaTz5";
    };
    security.sudo.wheelNeedsPassword = lib.mkForce false;

    # services
    services.pcscd.enable = true;

    # TODO(quality): these scripts use gpg; if I was doing it again I'd use sq/sequoia-pgp + oct/OpenPGP-card-tools
    programs.gnupg.agent.enable = true;
    programs.gnupg.agent.pinentryPackage = pkgs.pinentry-tty;
    hardware.gpgSmartcards.enable = true;

    environment.etc."issue".text = docstr;
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
    ]++[
      /**
        Implements various helper scripts. Refer to `modules/hosts/cryptid.nix` and `docs/cryptid-protocol.md` for details. These scripts help automate creation and management of a single cryptographic identity with sensible parameters and disaster response pathways. The scripts won't be useful to you if your needs are more elaborate.
      */

      # utility scripts

      (pkgs.writeShellScriptBin "_debug" ''
        # source to declare a bunch of variables to reduce interactions
        export CRYPTID_DEBUG=1
        export ${env.name}="MrDebug"
        export ${env.email}="d@d.com"
        pass="password123"
        export ${env.vaultpass}=$pass
        export ${env.yubi.fido.pin}=$pass
        export ${env.yubi.pgp.pin}=$pass
        export ${env.yubi.piv.pin}=7654321
        echo "Debug vars set"
      '')

      (pkgs.writeShellScriptBin "print_keyid" ''
        set -eo pipefail
        ${bash-get-keyid}
        echo ${"$" + env.keyid}
      '')

      (pkgs.writeShellScriptBin "print_ykserial" ''
          set -eo pipefail
          ${bash-get-yubiserial}
          echo ${"$" + env.yubi.serial}
      '')

      # ensures various /persist/ folders exist in preparation for writing
      (pkgs.writeShellScriptBin "mkdirs" ''
        set -euo pipefail
        dirs=( ${builtins.concatStringsSep " " mkdirs} )
        for dir in "''${dirs[@]}"; do
          sudo mkdir -p "$dir"
        done
      '')

      # returns the filepath with the filename prefixed with a timestamp
      (pkgs.writeShellScriptBin "timestamped_now" ''
        set -euo pipefail
        path="$1"
        dir=$(dirname "$path")
        base=$(basename "$path")
        ts=$(date +%Y%m%dT%H%M%S)
        echo "''${dir}/''${base}.''${ts}"
      '')

      # returns the filepath with most recent prefixed filename
      (pkgs.writeShellScriptBin "timestamped_last" ''
        set -euo pipefail
        path="$1"
        dir=$(dirname "$path")
        base=$(basename "$path")
        # lexicographically sort time-prefixed files and pick the last one
        last=$(find "$dir" -maxdepth 1 -name "''${base}.*" | sort | tail -n 1)
        if [ -z "$last" ]; then
            # Fallback: if no timestamped versions exist, complain but return the original path
            echo "Error: didn't find timestamp-version files; did the user run scripts out-of-order? Just returning '$1'" >&2
            echo "$path"
        else
            echo "$last"
        fi
      '')

      # Lesser scripts: medium-level abstractions

      (pkgs.writeShellScriptBin "?" ''
        cat << EOF
        ${docstr}
        EOF
      '')

      (pkgs.writeShellScriptBin "list-files" ''
        set -eo pipefail
        printf "\n${path-mount-persist}/\n"
        find "${path-mount-persist}/." -print | sed -e 's;[^/]*/;|____;g;s;____|; |;g'
        if veracrypt --text --list | grep -q "${path-mount-vault}"; then
          printf "\n${path-mount-vault}/\n"
          find "${path-mount-vault}/." -print | sed -e 's;[^/]*/;|____;g;s;____|; |;g'
        else
          echo "Vault not open."
        fi
      '')

      (mkScript "list-pgp" ''
        printf "\nYUBI: OpenPGP\n"
        ykman openpgp info
        printf "\nGPG: Card Status\n"
        gpg --card-status
        printf "\nGPG: Secret Keys\n"
        gpg -K --with-keygrip
      '')

      (mkScript "list-ssh" ''
        source load-secrets
        echo "YUBI: FIDO credentials"
        ykman fido credentials list --pin "${"$" + env.yubi.fido.pin}"
        FILE=$(timestamped_last "${pathv-emerg-ssh-public}")
        echo "Most recent SSH Breakglass: $FILE"
        cat $FILE
      '')

      (mkScript "list-age" ''
        echo "YUBI: PIV Slots"
        ykman piv info
        FILE=$(timestamped_last "${pathv-emerg-age-public}")
        echo "Most recent breakglass: $FILE"
        cat $FILE
      '')

      (mkScript "list-yubicodes" ''
        YUBI_FILE=$(timestamped_last "${pathv-yubicodes}")
        printf "\nYUBI: passcodes in $YUBI_FILE \n"
        cat $YUBI_FILE
      '')

      (mkScript "load-secrets" ''
        YUBI_FILE=$(timestamped_last "${pathv-yubicodes}")
        source $YUBI_FILE
        printf "Loaded:\n\t$YUBI_FILE\n\n"
      '')

      (mkScript "vault-init" ''
        if [ -f "${path-vault-file}" ]; then
          echo "Error: vault already exists." >&2
          return 1;
        fi
        ${bash-ask-confirm-pass "VAULTPASS" "new vault"}
        echo Creating vault ...
        creation_args=(
          --text
          --create "${path-vault-file}"
          --volume-type "normal"
          --filesystem "${vault-fs}"
          --hash "${vault-hasher}"
          --encryption "${vault-crypto}"
          --size "${vault-size}"
          --password "${"$" + env.vaultpass}"
          --pim "${vault-pim}"
          --keyfiles ""
          --random-source=/dev/urandom
        )
        sudo veracrypt "''${creation_args[@]}"
      '')

      (mkScript "vault-open" ''
        if veracrypt --text --list | grep -q "${path-mount-vault}"; then
          echo "Vault is open."
          return 0
        fi
        [[ -z "${"$" + env.vaultpass}" ]] && read -rsp "Enter existing vault password: " ${env.vaultpass}
        echo Opening vault ...
        sudo mkdir -p ${path-mount-vault}
        mounting_args=(
          --text
          --mount "${path-vault-file}"
          --password "${"$" + env.vaultpass}"
          --pim "${vault-pim}"
          --keyfiles ""
          --protect-hidden no
          "${path-mount-vault}"
        )
        sudo veracrypt "''${mounting_args[@]}"
        mkdirs
        sudo bash -c '
          chmod -R u+rX "${path-mount-persist}"
          chown -R user:wheel "${path-mount-persist}"
          chmod -R u+rwX,g+rwX,o-rwx "${path-mount-persist}"
        '
      '')

      (pkgs.writeShellScriptBin "vault-cd" ''cd "${path-mount-vault}"'')

      (mkScript "vault-close" ''
        # set persist to be read-only by user
        sudo chown -R user:wheel "${path-mount-persist}"
        sudo chmod -R u+rX,go-rwx "${path-mount-persist}"
        # unmount
        sudo veracrypt --text --unmount "${path-mount-vault}"
        sync
      '')

      (mkScript "gpg-clean" ''
          gpgconf --kill gpg-agent 2>/dev/null || true
          if [ -d "$GNUPGHOME" ]; then
            rm -rf "$GNUPGHOME"
          fi
          ${bash-make-gnupg-home}
          echo "Refreshed $GNUPGHOME"
      '')

      (mkScript "gpg-new-rootkey" ''
        # Prompt for user details
        [[ -z "${"$" + env.name}" ]] && read -p "Enter your full name: " ${env.name}
        [[ -z "${"$" + env.email}" ]] && read -p "Enter your email address: " ${env.email}
        echo Generating root key ...
        cat <<EOF | gpg -q --batch --pinentry-mode=loopback --passphrase "" --generate-key
        %no-protection
        Key-Type: ${pgp-rootkey-type}
        Key-Curve: ${pgp-rootkey-curve}
        Key-Usage: cert
        Passphrase: ""
        Name-Real: "${"$" + env.name}"
        Name-Email: "${"$" + env.email}"
        Expire-Date: 0
        Preferences: ${pgp-preferences}
        %commit
        %echo Root key created with email: '${"$" + env.email}'
        EOF
      '')

      (mkScript "gpg-new-subkeys" ''
        ${bash-get-keyid}
        echo "Creating sign subkey ..."
        gpg -q --quick-add-key --pinentry-mode=loopback --passphrase "" "${"$" + env.keyid}" "${pgp-sign-algorithm}" sign "${pgp-expiry-in-months}m"
        echo "Creating encrypt subkey ..."
        gpg -q --quick-add-key --pinentry-mode=loopback --passphrase "" "${"$" + env.keyid}" "${pgp-encrypt-algorithm}" encrypt "${pgp-expiry-in-months}m"
      '')

      (mkScript "gpg-rev-subkeys" ''
        ${bash-get-keyid}
        echo "Revoking the newest two GPG subkeys ..."

        expect -d << EXPECT_SCRIPT &> ${path-log-expectScript}

        ${expect-header}
        ${expect-gpgeditkey}

        proc revoke_key { keyindex {spawn ""} } {
          ${expect-default-spawn}
          oi "gpg>" "key \$keyindex" \$spawn
          oi "gpg>" "revkey" \$spawn
          oi "Do you really want to revoke" "y" \$spawn
          safe_expect "0 = No reason specified"  \$spawn
          oi "Your decision?" "0"  \$spawn
          oi "optional description" ""  \$spawn
          oi "Is this okay" "y"  \$spawn
          oi "gpg>" "key \$keyindex" \$spawn
        }

        spawn gpg --expert --pinentry-mode loopback --edit-key ${"$" + env.keyid}

        set index2 [count_subkeys]
        set index1 [expr {\$index2 - 1}]
        revoke_key \$index1
        revoke_key \$index2

        oi "gpg>" "save"
        safe_expect_end
        EXPECT_SCRIPT
        echo "Done."
      '')

      (mkScript "gpg-backup" ''
        ${bash-get-keyid}
        echo Creating GPG backup ...
        OUT_PRI=$(timestamped_now "${pathv-pgp-private}")
        OUT_REV=$(timestamped_now "${pathv-pgp-revoke}")
        OUT_PUB=$(timestamped_now "${pathv-pgp-public}")

        TMP_PRI=$(mktemp /tmp/gpg-secret.XXXXXX)
        gpg --yes --batch --export-secret-keys --armor ${"$" + env.keyid} > "$TMP_PRI"
        if [[ ! -s "$TMP_PRI" ]]; then
          echo "Error: Secret keys export failed (file is empty or missing)" >&2
          exit 1
        fi
        mv "$TMP_PRI" "$OUT_PRI"

        echo "Saved secret keys to: '$OUT_PRI'"
        TMP_REV=$(mktemp /tmp/gpg-revoke.XXXXXX)
        rm -rf "$TMP_REV"
        expect -d << EXPECT_SCRIPT &> ${path-log-expectScript}
        ${expect-header}
        spawn gpg --output "$TMP_REV" --gen-revoke "${"$" + env.keyid}"
        oi "Create a revocation certificate" "y"
        safe_expect "0 = No reason specified"
        oi "Your decision?" "0"
        oi "optional description" ""
        oi "Is this okay" "y"
        safe_expect_end
        EXPECT_SCRIPT
        if [[ ! -s "$TMP_REV" ]]; then
          echo "Error: Revocation certificate creation failed (file is empty or missing)" >&2
          exit 1
        fi
        mv "$TMP_REV" "$OUT_REV"
        echo "Saved revoke certificate to: '$OUT_REV'"

        TMP_PUB=$(mktemp /tmp/gpg-pub.XXXXXX)
        gpg --export --armor ${"$" + env.keyid} > "$TMP_PUB"
        if [[ ! -s "$TMP_PUB" ]]; then
          echo "Error: public key export failed (file is empty or missing)" >&2
          exit 1
        fi
        mv "$TMP_PUB" "$OUT_PUB"
        echo "Saved public keys to: $OUT_PUB"
      '')

      (mkScript "gpg-restore" ''
        TARGET=$(timestamped_last "${pathv-pgp-private}")
        echo "Importing most recent key: $TARGET"
        # ensure the agent is running
        gpgconf --launch gpg-agent
        sleep 1
        gpg --batch --import "$TARGET"
        ${bash-get-keyid}
        echo "Imported/Found key: ${"$" + env.keyid}"
        echo "${"$" + env.keyid}:6:" | gpg --import-ownertrust
        gpg --list-secret-keys
        gpg --card-status
      '')

      (mkScript "gpg-test" ''
        OLDHOME=$GNUPGHOME
        cleanup() {
            export GNUPGHOME="$OLDHOME"
        }
        trap cleanup EXIT ERR
        PRIV_PATH=$(timestamped_last "${pathv-pgp-private}")
        PUB_PATH=$(timestamped_last "${pathv-pgp-public}")
        printf "Verifying PGP root key...\nPrivate: $PRIV_PATH\nPublic:  $PUB_PATH\n"
        GNUPGHOME=$(mktemp -d)
        gpg --batch --import "$PRIV_PATH"
        ${bash-get-keyid}
        OUTPUT=$(mktemp /tmp/gpg-pub.XXXXXX)
        gpg --export --armor ${"$" + env.keyid} > "$OUTPUT"
        if [ "$(cat "$OUTPUT")" = "$(cat "$PUB_PATH")" ]; then echo "TEST PASSED"; else echo "FAIL: PGP CORRUPT OR INVALID" >&2; fi
        cleanup
        trap "" EXIT ERR
      '')

      (mkScript "ssh-emerg-make" ''
        echo Generating emergency SSH key ...
        TMP_DIR=$(mktemp -d)
        TMP_FILE="$TMP_DIR/sshkey"
        TMP_PRI="$TMP_FILE"
        TMP_PUB="''${TMP_FILE}.pub"
        OUT_PRI=$(timestamped_now "${pathv-emerg-ssh-private}")
        OUT_PUB=$(timestamped_now "${pathv-emerg-ssh-public}")

        ssh-keygen -t ed25519 -C "${emergency-label-ssh}" -f "$TMP_FILE" -N ""

        if [[ ! -s "$TMP_PRI" ]]; then
          echo "Error: private key creation failed (file is empty or missing)" >&2
          exit 1
        fi
        if [[ ! -s "$TMP_PUB" ]]; then
          echo "Error: public key creation failed (file is empty or missing)" >&2
          exit 1
        fi
        mv "$TMP_PRI" "$OUT_PRI"
        mv "$TMP_PUB" "$OUT_PUB"
        printf "Saved private key to: '$OUT_PRI'\nSaved public key to: '$OUT_PUB'\n"
      '')

      (mkScript "ssh-emerg-test" ''
        PRIV_PATH=$(timestamped_last "${pathv-emerg-ssh-private}")
        PUB_PATH=$(timestamped_last "${pathv-emerg-ssh-public}")
        printf "Verifying emergency SSH keys...\nPrivate: $PRIV_PATH\nPublic:  $PUB_PATH\n"
        OUTPUT=$(ssh-keygen -y -f "$PRIV_PATH")
        if [ "$OUTPUT" = "$(cat "$PUB_PATH")" ]; then echo "TEST PASSED"; else echo "FAIL: SSH CORRUPT OR INVALID" >&2; fi
      '')

      (mkScript "ssh-mergepubs" ''
          SK=$(timestamped_last "${pathv-ssh-public}")
          EM=$(timestamped_last "${pathv-emerg-ssh-public}")
          OUT=$(timestamped_now "${pathv-merged-pubs-ssh}")
          TMP_PUB=$(mktemp /tmp/merge-ssh.XXXXXX)
          cat "$SK" "$EM" >> "$TMP_PUB"
          mv "$TMP_PUB" "$OUT"
          echo "Created ssh public-keys file: '$OUT'"
      '')

      (mkScript "age-emerg-make" ''
        echo Generating emergency AGE key ...
        TMP_DIR=$(mktemp -d)
        TMP_FILE="$TMP_DIR/agekey"
        TMP_PRI="$TMP_FILE"
        TMP_PUB="''${TMP_FILE}.pub"
        OUT_PRI=$(timestamped_now "${pathv-emerg-age-private}")
        OUT_PUB=$(timestamped_now "${pathv-emerg-age-public}")

        age-keygen -pq -o "$TMP_PRI"
        age-keygen -y $TMP_PRI > "$TMP_PUB"

        mv "$TMP_PRI" "$OUT_PRI"
        mv "$TMP_PUB" "$OUT_PUB"
        printf "Saved private key to: '$OUT_PRI'\nSaved public key to: '$OUT_PUB'\n"
      '')

      (mkScript "age-emerg-test" ''
        PRIV_PATH=$(timestamped_last "${pathv-emerg-age-private}")
        PUB_PATH=$(timestamped_last "${pathv-emerg-age-public}")
        printf "Verifying emergency AGE keys...\nPrivate: $PRIV_PATH\nPublic:  $PUB_PATH\n"
        OUTPUT=$(age-keygen -y "$PRIV_PATH")
        if [ "$OUTPUT" == "$(cat "$PUB_PATH")" ]; then echo "TEST PASSED"; else echo "FAIL: AGE CORRUPT OR INVALID" >&2; fi
      '')

      (mkScript "age-mergepubs" ''
        [[ -z "${"$" + env.name}" ]] && read -p "Enter your full name: " ${env.name}
        [[ -z "${"$" + env.email}" ]] && read -p "Enter your email address: " ${env.email}
        LABEL="${"$" + env.name} <''${${env.email}}>"
        SK=$(timestamped_last "${pathv-age-public}")
        EM=$(timestamped_last "${pathv-emerg-age-public}")
        OUT=$(timestamped_now "${pathv-merged-pubs-age}")
        TMP_PUB=$(mktemp /tmp/merge-age.XXXXXX)
        echo "# $LABEL" >> "$TMP_PUB"
        cat "$SK" >> "$TMP_PUB"
        echo "# $LABEL (${emergency-label-age})" >> "$TMP_PUB"
        cat "$EM" >> "$TMP_PUB"
        mv "$TMP_PUB" "$OUT"
        echo "Created age public-keys file: '$OUT'"
      '')

      (mkScript "yubi-reset" ''
        ${bash-get-yubiserial}
        printf "Preparing to factory-reset YubiKey serial ${"$" + env.yubi.serial} ...\n\n!!!\n!!!   WARNING: ALL OPENPGP AND FIDO APPLETS WILL BE RESET ONCE YOU BEGIN!\n!!!\n\n"

        echo "Resetting FIDO ..."
        ykman --device "${"$" + env.yubi.serial}" fido reset
        echo "Resetting PIV ..."
        ykman --device "${"$" + env.yubi.serial}" piv reset --force
        echo "Resetting OpenPGP ..."
        ykman --device "${"$" + env.yubi.serial}" openpgp reset --force
        echo "Trying to disable NFC ..."
        ykman config nfc --disable-all --force || true
        echo "Trying to disable unused applets ..."
        ykman config usb --disable otp --force || true
        ykman config usb --disable u2f --force || true
        ykman config usb --disable oath --force || true
        ykman config usb --disable hsmauth --force || true
        printf "\nCompleted applet reset of: FIDO, OpenPGP, PIV.\nNFC and unused applets have been disabled.\n"
        # ask for PIV pin, 6~8 digits
        if [[ -z "${"$" + env.yubi.piv.pin}" ]]; then
            while true; do
                ${bash-ask-confirm-pass "${env.yubi.piv.pin}" "new YubiKey PIV PIN (6~8 digits)"}
                if [[ "${"$" + env.yubi.piv.pin}" =~ ^[0-9]{6,8}$ ]]; then
                    break
                else
                    echo "Invalid input. Please enter a PIN between 6 and 8 digits long."
                    unset ${env.yubi.piv.pin}
                fi
            done
        fi
        # use same passphrase for FIDO2 and OpenPGP
        if [[ -z "${"$" + env.yubi.fido.pin}" ]]; then
            while true; do
                ${bash-ask-confirm-pass "${env.yubi.fido.pin}" "new YubiKey OpenPGP and FIDO2 (ssh) passphrase longer than six alpha-numeric characters"}
                if [[ "${"$" + env.yubi.fido.pin}" =~ ^[a-zA-Z0-9]{6,}$ ]]; then
                    break
                else
                    echo "Invalid input. Please enter an alpha-numeric passphrase with 6 or more characters."
                    unset ${"$" + env.yubi.fido.pin}
                fi
            done
        fi
        ${env.yubi.pgp.pin}=${"$" + env.yubi.fido.pin}
        # generate management & unblock pins
        ${env.yubi.pgp.admin}=$(diceware -l effshort2 -d '-' -n 5)
        ${env.yubi.pgp.reset}=$(diceware -l effshort2 -d '-' -n 5)
        ${env.yubi.piv.puk}=$({ tr -dc '0-9' < /dev/urandom || :; } | head -c 8)
        YUBI_FILE=$(timestamped_now "${pathv-yubicodes}")
        echo "# YubiKey applications passphrases for OpenPGP, PIV, and FIDO" >> "$YUBI_FILE"
        echo "${env.yubi.pgp.admin}=${"$" + env.yubi.pgp.admin}" >> "$YUBI_FILE"
        echo "${env.yubi.pgp.pin}=${"$" + env.yubi.pgp.pin}" >> "$YUBI_FILE"
        echo "${env.yubi.pgp.reset}=${"$" + env.yubi.pgp.reset}" >> "$YUBI_FILE"
        echo "${env.yubi.piv.pin}=${"$" + env.yubi.piv.pin}" >> "$YUBI_FILE"
        echo "${env.yubi.piv.puk}=${"$" + env.yubi.piv.puk}" >> "$YUBI_FILE"
        echo "${env.yubi.fido.pin}=${"$" + env.yubi.fido.pin}" >> "$YUBI_FILE"

        printf "\nInitializing Yubikey OpenPGP ...\n"
        ykman openpgp access set-retries ${yubi-retries-pin} ${yubi-retries-admin} ${yubi-retries-puk} --admin-pin "${yubi-stock-pgp-admin}" --force
        ykman openpgp access set-signature-policy --admin-pin "${yubi-stock-pgp-admin}" "${yubi-pass-policy}"
        ykman openpgp access change-pin --pin ${yubi-stock-pgp-pin} --new-pin "${"$" + env.yubi.pgp.pin}"
        ykman openpgp access change-admin-pin --admin-pin ${yubi-stock-pgp-admin} --new-admin-pin "${"$" + env.yubi.pgp.admin}"
        ykman openpgp access change-reset-code --admin-pin "${"$" + env.yubi.pgp.admin}" --reset-code "${"$" + env.yubi.pgp.reset}"
        ykman openpgp keys set-touch --admin-pin "${"$" + env.yubi.pgp.admin}" --force "sig" "${yubi-touch-policy}"
        ykman openpgp keys set-touch --admin-pin "${"$" + env.yubi.pgp.admin}" --force "enc" "${yubi-touch-policy}"
        ykman openpgp keys set-touch --admin-pin "${"$" + env.yubi.pgp.admin}" --force "aut" "${yubi-touch-policy}"
        ykman openpgp keys set-touch --admin-pin "${"$" + env.yubi.pgp.admin}" --force "att" "${yubi-touch-policy}"

        printf "\nInitializing Yubikey PIV ...\n"
        ykman piv access set-retries ${yubi-retries-pin} ${yubi-retries-puk} --pin "${yubi-stock-piv-pin}" --management-key "${yubi-stock-piv-mgt}" --force
        ykman piv access change-pin --pin "${yubi-stock-piv-pin}" --new-pin "${"$" + env.yubi.piv.pin}"
        ykman piv access change-management-key --algorithm "${yubi-piv-management-alg}" --protect --force --management-key "${yubi-stock-piv-mgt}" --pin "${"$" + env.yubi.piv.pin}"
        ykman piv access change-puk --puk "${yubi-stock-piv-puk}" --new-puk "${"$" + env.yubi.piv.puk}"

        printf "\nInitializing Yubikey FIDO2 ...\n"
        ykman fido access change-pin --new-pin "${"$" + env.yubi.fido.pin}"

        printf "\nDone. All pins have been saved in '$YUBI_FILE'\nConsider using a password manager for your non-admin/management PINs.\nYou can further customize the card with 'gpg-card help'\n"
      '')

      (mkScript "yubi-new-ssh" ''
        [[ -z "${"$" + env.email}" ]] && read -p "Enter your email address: " ${env.email}
        [[ -z "${"$" + env.yubi.piv.pin}" ]] && read -p "Enter YubiKey PIV PIN: " ${env.yubi.piv.pin}
        LABEL="ssh_sk-$(date '+%Y')#''${${env.email}}"
        TMP_DIR=$(mktemp -d)
        TMP_FILE="$TMP_DIR/sshkey"
        TMP_PRI="$TMP_FILE"
        TMP_PUB="''${TMP_FILE}.pub"
        OUT_PRI=$(timestamped_now "${pathv-ssh-stub}")
        OUT_PUB=$(timestamped_now "${pathv-ssh-public}")
        printf "\n\nPlease touch your YubiKey in a moment.\n\n"
        expect -d << EXPECT_SCRIPT &> ${path-log-expectScript}
        ${expect-header}
        spawn ssh-keygen -t ed25519-sk -O resident -O application=ssh: -C "$LABEL" -f "$TMP_PRI" -N ""
        set timeout 45
        expect "PIN" { safe_send "${"$" + env.yubi.fido.pin}" } ${expect-error-cases}
        set timeout \$default_timeout_value
        while {1} {
          expect "Overwrite" { safe_send "y" } eof {break} ${expect-error-cases}
        }
        EXPECT_SCRIPT
        mv "$TMP_PRI" "$OUT_PRI"
        mv "$TMP_PUB" "$OUT_PUB"
        printf "Saved private stub to: '$OUT_PRI'\nSaved public key to: '$OUT_PUB'\n"
      '')

      # TODO(crypt): age: post-quantum yubikey resident, pending https://github.com/str4d/age-plugin-yubikey/issues/217
      # TODO(quality): pass pin by environmental varialbe, pending https://github.com/str4d/age-plugin-yubikey/issues/20
      (mkScript "yubi-new-age" ''
        ${bash-get-yubiserial}
        [[ -z "${"$" + env.yubi.piv.pin}" ]] && read -p "Enter YubiKey PIV PIN: " ${env.yubi.piv.pin}
        [[ -z "${"$" + env.email}" ]] && read -p "Enter your email address: " ${env.email}
        LABEL="age_sk-$(date '+%Y')#''${${env.email}}"
        TMP_DIR=$(mktemp -d)
        TMP_FILE="$TMP_DIR/agekey"
        TMP_PRI="$TMP_FILE"
        TMP_PUB="''${TMP_FILE}.pub"
        OUT_PRI=$(timestamped_now "${pathv-age-stub}")
        OUT_PUB=$(timestamped_now "${pathv-age-public}")
        printf "\n\nPlease touch your YubiKey in a moment.\n\n"
        expect -d << EXPECT_SCRIPT &> ${path-log-expectScript}
        ${expect-header}
        spawn age-plugin-yubikey --generate --serial "${"$" + env.yubi.serial}" --slot "${yubi-age-piv-slot}" --pin-policy "${yubi-age-pass-policy}" --name "$LABEL" --touch-policy "${yubi-age-touch-policy}" --force
        set timeout 45
        expect "Enter PIN for YubiKey" { safe_send "${"$" + env.yubi.piv.pin}" } ${expect-error-cases}
        set timeout \$default_timeout_value
        safe_expect_end
        EXPECT_SCRIPT
        age-plugin-yubikey --identity --serial "${"$" + env.yubi.serial}" --slot "${yubi-age-piv-slot}" > $TMP_PRI 2> $TMP_PUB
        sed -i 's/^Recipient: //' $TMP_PUB
        mv "$TMP_PRI" "$OUT_PRI"
        mv "$TMP_PUB" "$OUT_PUB"
        printf "Saved private stub to: '$OUT_PRI'\nSaved public key to: '$OUT_PUB'\n"
      '')

      (mkScript "yubi-move-keys" ''
        ${bash-get-keyid}
        [[ -z "${"$" + env.yubi.pgp.admin}" ]] && read -p "Enter your YubiKey Admin Password: " ${env.yubi.pgp.admin}
        echo "Moving the newest two GPG subkeys to YubiKey ..."

        expect -d << EXPECT_SCRIPT &> ${path-log-expectScript}

        ${expect-header}
        ${expect-gpgeditkey}

        # move key number index to the yubikey (assumes no subkey passphrase; only yubi admin pin)
        proc move_key_to_card { keyindex selection yubiadminpin overwrite {spawn ""} } {
          ${expect-default-spawn}
          oi "gpg>" "key \$keyindex" \$spawn
          oi "gpg>" "keytocard" \$spawn
          oi "Your selection?" "\$selection" \$spawn
          while {1} {
            expect -i \$spawn \
              "Enter passphrase: " { safe_send \$yubiadminpin \$spawn } \
              "Replace existing key? (y/N)" {
                  if {\$overwrite} {
                      safe_send "y" \$spawn
                  } else {
                      puts "Error: key already exists"
                      exit 4
                  }
              } \
              "Invalid" {
                puts "Something wen't wrong"
                exit 1
              } \
              "gpg>" {
                # deselect
                safe_send "key \$keyindex" \$spawn
                break
              } \
              ${expect-error-cases}
          }
          puts "Moved key \$keyindex selection \$selection to smartcard."
        }

        spawn gpg --expert --pinentry-mode loopback --edit-key ${"$" + env.keyid}

        set overwrite true
        set index2 [count_subkeys]
        set index1 [expr {\$index2 - 1}]
        move_key_to_card \$index1 1 "${"$" + env.yubi.pgp.admin}" \$overwrite
        move_key_to_card \$index2 2 "${"$" + env.yubi.pgp.admin}" \$overwrite

        oi "gpg>" "save"
        safe_expect_end
        EXPECT_SCRIPT
        gpg --card-status
      '')

      (mkScript "yubi-extend" ''
        gpg --card-status
        gpg -K
        ${bash-get-keyid}
        gpg --quick-set-expire ${"$" + env.keyid} '${pgp-expiry-in-months}m' '*'
        echo "Current subkeys:"
        gpg --list-secret-keys --keyid-format LONG "${"$" + env.keyid}"
      '')

      # Greater scripts: high-level workflow compositions

      (mkScript "first-time-init" ''
        # make vault
        source vault-init
        source vault-open
        # make root key
        source gpg-new-rootkey
        source gpg-new-subkeys
        source gpg-backup
        # make "breakglass" emergency keys
        source ssh-emerg-make
        source ssh-emerg-test
        source age-emerg-make
        source age-emerg-test
        # lockup and prep for shutdown
        source vault-close
        touch ${path-firsttimeflag}
        printf "\n\n---\nDone. Please reboot and run 'init-yubikey' to complete initialization.\n"
      '')

      (mkScript "init-yubikey" ''
        if [ -f ${path-firsttimeflag} ]; then
            printf "Error: '${path-firsttimeflag}' exists; dirty environment.\nIt's strongly recommended that you reboot to validate the recovery paths.\nAlternatively, you can run 'init-yubikey-dirty'.\nAborting.\n" >&2
            return 1
        fi
        # validate recovery paths
        source vault-open
        source gpg-restore
        source gpg-test
        source ssh-emerg-test
        source age-emerg-test
        # provision yubikey, pgp subkeys, age keys, ssh keys.
        source yubi-reset
        source yubi-new-ssh
        source yubi-new-age
        source yubi-move-keys
        source age-mergepubs
        source ssh-mergepubs
        source vault-close
      '')

      (mkScript "init-yubikey-dirty" ''
        echo "Deleting GPG state ..."
        source gpg-clean
        rm -rf "${path-firsttimeflag}"
        source init-yubikey
        touch "${path-firsttimeflag}"
      '')

      (mkScript "extend-subkeys" ''
        source vault-open
        source load-secrets
        source gpg-restore
        source yubi-extend
        source list-pgp
        source vault-close
      '')

      (mkScript "rotate-subkeys" ''
        source vault-open
        source load-secrets
        source gpg-restore
        source gpg-rev-subkeys
        source gpg-new-subkeys
        source gpg-backup
        source yubi-move-keys
        source list-pgp
        source vault-close
      '')

      (mkScript "rotate-sshkeys" ''
        source vault-open
        source load-secrets
        source ssh-emerg-make
        source ssh-emerg-test
        source yubi-new-ssh
        source ssh-mergepubs
        source list-ssh
        source vault-close
      '')

      (mkScript "rotate-agekeys" ''
        source vault-open
        source load-secrets
        source age-emerg-make
        source age-emerg-test
        source yubi-new-age
        source age-mergepubs
        source list-age
        source vault-close
      '')

      (mkScript "rotate-all" ''
        source vault-open
        source load-secrets
        source age-emerg-make
        source age-emerg-test
        source yubi-new-age
        source age-mergepubs
        source ssh-emerg-make
        source ssh-emerg-test
        source yubi-new-ssh
        source ssh-mergepubs
        source gpg-restore
        source gpg-rev-subkeys
        source gpg-new-subkeys
        source gpg-backup
        source yubi-move-keys
        source list-pgp
        source list-ssh
        source list-age
        source vault-close
      '')

      (mkScript "verify" ''
        source vault-open
        source gpg-test
        source ssh-emerg-test
        source age-emerg-test
        source vault-close
      '')
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
  flake.apps."${system}"."${bootable}".program =
  let
    iso = inputs.self.nixosConfigurations.${hostname}.config.system.build.isoImage;
    pkgs = inputs.cryptid-nixpkgs.legacyPackages."${system}";
  in
    toString (pkgs.writeShellScript bootable ''
      set -euo pipefail
      echo "Starting @ $(date +%Y%m%dT%H%M%S)"

      if [ -z "$1" ]; then
        echo "Usage: nix run .#${bootable} -- /dev/sdX"
        echo "WARNING: This is a destructive operation."
        exit 1
      fi

      DEV="$1"

      if [ ! -b "$DEV" ]; then
        echo "Error: $DEV is not a block device"
        exit 1
      fi

      echo "WARNING: This will ERASE ALL DATA on $DEV"
      read -p "Press Y to continue, any other key to abort: " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
      fi

      printf "\nWiping $DEV ...\n"
      sudo wipefs -a "$DEV"
      echo ",," | sudo sfdisk --quiet "$DEV"
      sleep 1
      udevadm settle
      sleep 2

      printf "\nWriting ISO to $DEV ...\n"
      cat "${iso}/iso"/*.iso | sudo dd of="$DEV" bs=4M conv=fsync && sync
      sleep 1
      udevadm settle
      sleep 2

      printf "\nAppending partition to $DEV ...\n"
      echo ", ,L" | sudo sfdisk --append --quiet "$DEV"
      sleep 1
      udevadm settle
      sleep 2

      LAST_PART=$(sudo partx -rgo NR "$DEV" | tail -1)
      printf "\nFormatting ''${DEV}''${LAST_PART} as btrfs...\n"
      sudo ${pkgs.btrfs-progs}/bin/mkfs.btrfs -L "${persist-partition-label}" -f -m dup -d dup -M -q "''${DEV}''${LAST_PART}"

      echo "Done @ $(date +%Y%m%dT%H%M%S)"
  '');
}
