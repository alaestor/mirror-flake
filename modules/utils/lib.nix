{
  inputs,
  lib,
  ...
}:
{

  options = {

    flake.lib = lib.mkOption {
      type = lib.types.attrsOf lib.types.unspecified;
      default = { };
    };

  };

  config.flake.lib = rec {

    zipLists = first: second:
      if builtins.length first != builtins.length second then
        throw "zipLists: lists must have equal lengths"
      else
        lib.imap0
          (index: value: {
            first = value;
            second = builtins.elemAt second index;
          })
          first;

    math = {
      pow = base: exponent:
        if exponent < 0 then
          throw "math.pow: negative exponents are unsupported"
        else
          lib.foldl' (result: _: result * base) 1 (builtins.genList (_: null) exponent);
    };


    /**
      ## `unit-systems` usage:

      ```nix
      size-in-kilobytes = 10 * self.lib.unit-systems.SI.bytes.kB;
      size-in-mebibits  = 10 * self.lib.unit-systems.IEC.bits.Mib;
      size-in-mebibytes = 10 * self.lib.unit-systems.IEC.bytes.MiB;
      ```
    */
    unit-systems =
    let
      table = base: names:
        let
          exponents = lib.range 0 (builtins.length names - 1);
          pairs = zipLists names exponents;
        in
          builtins.listToAttrs (
            map
              (pair: {
                name = pair.first;
                value = math.pow base pair.second;
              })
              pairs
          );
    in {
      SI = {
        bytes = table 1000 [
          "B"
          "kB"
          "MB"
          "GB"
          "TB"
        ];

        bits = table 1000 [
          "b"
          "kb"
          "Mb"
          "Gb"
          "Tb"
        ];
      };

      IEC = {
        bytes = table 1024 [
          "B"
          "KiB"
          "MiB"
          "GiB"
          "TiB"
        ];

        bits = table 1024 [
          "b"
          "Kib"
          "Mib"
          "Gib"
          "Tib"
        ];
      };
    };

    /**
      ## `unit-systems` usage:

      ```nix
      size-in-kilobytes = self.lib.units.SI.bytes.kB 10;
      size-in-mebibits  = self.lib.units.IEC.bits.Mib 10;
      size-in-mebibytes = self.lib.units.IEC.bytes.MiB 10;
      ```
    */
    units =
      builtins.mapAttrs
        (_system: categories:
          builtins.mapAttrs
            (_category: factors:
              builtins.mapAttrs
                (_unit: factor: value: value * factor)
                factors)
            categories)
        unit-systems;

    /**
      Creates a script which writes a NixOS ISO to a block device. `postWrite`
      can add host-specific operations after the ISO has been written.
    */
    mkIsoWriter =
      {
        name,
        pkgs,
        iso,
        postWrite ? "",
      }:
      pkgs.writeShellScript "mkbootable-${name}" ''
        set -euo pipefail
        echo "Starting @ $(date +%Y%m%dT%H%M%S)"

        if [ -z "''${1:-}" ]; then
          echo "Usage: nix run .#mkbootable-${name} -- /dev/sdX"
          printf "\nAvailable removable devices:\n"
          lsblk -d -o NAME,SIZE,TRAN,MODEL,RM -l | awk 'NR==1 || $5 == "1" { $5=""; print }' | column -t | sed 's/^/  /'
          printf "\nWARNING: This is a destructive operation."
          exit 1
        fi

        DEV="$1"

        if [ ! -b "$DEV" ]; then
          echo "Error: $DEV is not a block device"
          exit 1
        fi

        echo "WARNING: This will ERASE ALL DATA on $DEV"
        read -r -p "Press Y to continue, any other key to abort: " -n 1 REPLY
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
          echo "Aborted."
          exit 1
        fi

        printf "\nWiping %s ...\n" "$DEV"
        sudo wipefs -a "$DEV"
        echo ",," | sudo sfdisk --quiet "$DEV"
        sleep 1
        udevadm settle
        sleep 2

        printf "\nWriting ISO to %s ...\n" "$DEV"
        cat "${iso}"/iso/*.iso | sudo dd of="$DEV" bs=4M conv=fsync
        sync
        sleep 1
        udevadm settle
        sleep 2

        ${postWrite}

        echo "Done @ $(date +%Y%m%dT%H%M%S)"
      '';

    /**
      Creates a nixos-anywhere deployer for a host using the `ssh-host` and
      `standard-disk` modules.
    */
    mkNixosAnywhereDeployer = {
      name,
      pkgs,
      system-config,
    }: pkgs.writeShellApplication {
      name = "deploy-${name}";
      runtimeInputs = with pkgs; [ age age-plugin-yubikey nixos-anywhere openssh ];
      text = ''
        if [ -z "''${1:-}" ]; then
          printf "Requires one positional argument: <user>@<ip>\n\nUsage: nix run .#deploy-${name} -- root@192.168.0.5\n"
          exit 1
        fi
        TARGET=$1
        shift

        echo "[$(date +%Y%m%dT%H%M%S)] Starting deploying '${name}' to '$TARGET'"

        # Contents of this directory are copied to the installed system root.
        STAGING_DIR=$(mktemp -d)
        DEPLOY_KEY_DIR=$(mktemp -d)
        DEPLOY_KEY="$DEPLOY_KEY_DIR/nixos-anywhere"
        cleanup() { rm -rf "$STAGING_DIR" "$DEPLOY_KEY_DIR" "''${KEY_GENERATION_DIR:-}"; }
        trap cleanup ERR EXIT

        # Generate an ephemeral deployment identity.
        ssh-keygen \
          -q \
          -t ed25519 \
          -N "" \
          -C "nixos-anywhere-${name}" \
          -f "$DEPLOY_KEY"

        echo "Authorizing ephemeral deployment key on $TARGET..."

        KNOWN_HOSTS="$DEPLOY_KEY_DIR/known_hosts"

        # This is the only connection that should require the YubiKey.
        ssh -o UserKnownHostsFile="$KNOWN_HOSTS" -o StrictHostKeyChecking=accept-new "$TARGET" '
          umask 077
          mkdir -p ~/.ssh
          touch ~/.ssh/authorized_keys
          cat >> ~/.ssh/authorized_keys
        ' < "$DEPLOY_KEY.pub"

        # Confirm that SSH can authenticate exclusively with the ephemeral key.
        ssh \
          -i "$DEPLOY_KEY" \
          -o IdentitiesOnly=yes \
          -o IdentityAgent=none \
          -o UserKnownHostsFile="$KNOWN_HOSTS" -o StrictHostKeyChecking=accept-new \
          -o BatchMode=yes \
          "$TARGET" true

        ${lib.optionalString system-config.ssh-host.initrd.enable ''
            # --- Locate the flake root ---
            FLAKE_ROOT="$PWD"
            while [ "$FLAKE_ROOT" != "/" ] && [ ! -f "$FLAKE_ROOT/flake.nix" ]; do
              FLAKE_ROOT="$(dirname "$FLAKE_ROOT")"
            done
            if [ ! -f "$FLAKE_ROOT/flake.nix" ]; then
              echo "ERROR: flake.nix not found. Run 'nix run' from inside your flake repo." >&2
              exit 1
            fi

            HOST="${name}"
            SECRETS_DIR="$FLAKE_ROOT/secrets/hosts/$HOST"
            AGE_FILE="$SECRETS_DIR/initrd-hostkey.age"
            AGE_IDENTITY_FILE="$FLAKE_ROOT/secrets/age_sk.txt"
            RECIPIENT_FILE="$FLAKE_ROOT/data/identities/cryptidprotocol_age"
            STAGING_KEYPATH="''${STAGING_DIR}${system-config.ssh-host.initrd.hostKeyPath}"
            install -d -m755 "$(dirname "''${STAGING_KEYPATH}")"

            # Create and retain a stable initrd host key. The first installation
            # stages the generated key directly, avoiding a second deploy.
            if [ ! -f "$AGE_FILE" ]; then
              if [ ! -f "$RECIPIENT_FILE" ]; then
                echo "ERROR: age recipient file not found: $RECIPIENT_FILE" >&2
                exit 1
              fi

              echo "No initrd-hostkey.age for $HOST, generating and encrypting..."
              install -d -m700 "$SECRETS_DIR"
              KEY_GENERATION_DIR=$(mktemp -d)
              GENERATED_KEY="$KEY_GENERATION_DIR/initrd-hostkey"
              ssh-keygen -q -t ed25519 -N "" -C "''${HOST}_initrd" -f "$GENERATED_KEY"
              age -R "$RECIPIENT_FILE" -o "$AGE_FILE.tmp" "$GENERATED_KEY"
              mv "$AGE_FILE.tmp" "$AGE_FILE"
              mv "$GENERATED_KEY.pub" "$SECRETS_DIR/initrd-hostkey.pub"
              install -m600 "$GENERATED_KEY" "$STAGING_KEYPATH"
              rm -rf "$KEY_GENERATION_DIR"
              KEY_GENERATION_DIR=""

              echo "Created $AGE_FILE"
              echo "Initrd SSH host public key (record it for host verification):"
              cat "$SECRETS_DIR/initrd-hostkey.pub"
            else
              if [ ! -r "$AGE_IDENTITY_FILE" ]; then
                echo "ERROR: age identity file not found or unreadable: $AGE_IDENTITY_FILE" >&2
                echo "An identity matching a recipient in $RECIPIENT_FILE is required to decrypt $AGE_FILE." >&2
                exit 1
              fi

              printf "\n\n\tDECRYPTING AGE SECRET - MAY REQUIRE FIDO2 PIN\n\n"

              age --decrypt --identity "$AGE_IDENTITY_FILE" "$AGE_FILE" > "$STAGING_KEYPATH"
              chmod 600 "$STAGING_KEYPATH"
            fi
        ''}

        # create the password file for luks setup
        while true; do
          echo -n "Enter LUKS passphrase for partitioning: "
          read -r -s PASSPHRASE
          echo
          echo -n "Confirm LUKS passphrase: "
          read -r -s PASSPHRASE_CONFIRM
          echo
          if [ "''${PASSPHRASE}" = "''${PASSPHRASE_CONFIRM}" ]; then
            break
          else
            echo "Passphrases do not match. Please try again."
          fi
        done
        # --extra-files is copied only to the installed system, after disko has
        # run. Disko needs this file in the live installer instead.
        LUKS_KEY_FILE="$STAGING_DIR/luks-setup-password"
        echo -n "''${PASSPHRASE}" > "$LUKS_KEY_FILE"
        chmod 600 "$LUKS_KEY_FILE"

        # run nixos-anywhere
        nixos-anywhere \
          -i "$DEPLOY_KEY" \
          --ssh-option IdentitiesOnly=yes \
          --ssh-option IdentityAgent=none \
          --ssh-option BatchMode=yes \
          --ssh-option "UserKnownHostsFile=$KNOWN_HOSTS" \
          --ssh-option StrictHostKeyChecking=accept-new \
          --disk-encryption-keys \
            "${system-config.standard-disk.luks-setup-password-file}" \
            "$LUKS_KEY_FILE" \
          --extra-files "$STAGING_DIR" \
          --flake "${inputs.self}#${name}" \
          --target-host "$TARGET" \
          "$@"

        echo "[$(date +%Y%m%dT%H%M%S)] Finished deploying '${name}' to '$TARGET'"
      '';
    };

  };
}
