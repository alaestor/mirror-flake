# shellcheck shell=bash
# Sourced by the deployer after its private staging directory and cleanup trap
# are installed. Backup/public temporary files stay beside their destinations
# so hard-link publication is atomic and refuses to overwrite another writer.
stage_host_key() {
  local basename=$1 destination=$2 label=$3
  local backup="$HOSTKEYS_DIR/$basename.age"
  local public="$PUBLIC_KEYS_DIR/$basename.pub"
  local staged="$STAGING_DIR$destination"
  local derived derived_type derived_blob expected_type expected_blob _comment

  case "$destination" in
    /*) ;;
    *) echo "ERROR: host-key destination must be absolute: $destination" >&2; exit 1 ;;
  esac
  case "$destination" in
    */../*|*/..|*/./*|*/.)
      echo "ERROR: host-key destination must not contain dot segments: $destination" >&2
      exit 1
      ;;
  esac

  install -d -m755 "$(dirname "$staged")"
  if [ -e "$backup" ]; then
    if [ ! -r "$public" ]; then
      echo "ERROR: $label backup exists without a readable public identity: $public" >&2
      exit 1
    fi
    if [ ! -r "$AGE_IDENTITY_FILE" ]; then
      echo "ERROR: administrative age identity is unreadable: $AGE_IDENTITY_FILE" >&2
      exit 1
    fi
    echo "Decrypting $label host-key backup; this may require the administrative token."
    age --decrypt --identity "$AGE_IDENTITY_FILE" "$backup" > "$staged"
  else
    if [ -e "$public" ]; then
      echo "ERROR: $label public identity exists without its encrypted backup: $public" >&2
      echo "Refusing to generate a replacement identity." >&2
      exit 1
    fi
    if [ "${#ADMINISTRATIVE_RECIPIENTS[@]}" -eq 0 ]; then
      echo "ERROR: no administrative age recipients configured." >&2
      exit 1
    fi

    echo "Generating a new $label host identity."
    ssh-keygen -q -t ed25519 -N "" -C "$label" -f "$staged"
    install -d -m700 "$HOSTKEYS_DIR"
    install -d -m755 "$PUBLIC_KEYS_DIR"
    BACKUP_TEMP=$(mktemp "$HOSTKEYS_DIR/.$basename.age.XXXXXX")
    PUBLIC_TEMP=$(mktemp "$PUBLIC_KEYS_DIR/.$basename.pub.XXXXXX")
    local recipient_args=() recipient
    for recipient in "${ADMINISTRATIVE_RECIPIENTS[@]}"; do
      recipient_args+=(-r "$recipient")
    done
    age "${recipient_args[@]}" -o "$BACKUP_TEMP" "$staged"
    cp "$staged.pub" "$PUBLIC_TEMP"
    chmod 644 "$PUBLIC_TEMP"
    ln -T -- "$BACKUP_TEMP" "$backup"
    ln -T -- "$PUBLIC_TEMP" "$public"
    rm -f -- "$BACKUP_TEMP" "$PUBLIC_TEMP"
    BACKUP_TEMP=""
    PUBLIC_TEMP=""

    echo "Created $backup"
    echo "Created $public"
    echo "Review and commit both files after deployment. Declare the system-key"
    echo "backup in secrets/secrets.nix with administrative recipients only;"
    echo "initrd backups need no Agenix rule. Rekey runtime secrets for new system identities."
  fi

  chmod 600 "$staged"
  derived=$(ssh-keygen -y -P "" -f "$staged")
  read -r derived_type derived_blob _comment <<< "$derived"
  derived="$derived_type $derived_blob"
  read -r expected_type expected_blob _comment < "$public" || true
  if [ "$expected_type" != ssh-ed25519 ] || [ "$derived" != "$expected_type $expected_blob" ]; then
    echo "ERROR: $label private key does not match $public; refusing deployment." >&2
    exit 1
  fi
  printf '%s\n' "$derived" > "$staged.pub"
  chmod 644 "$staged.pub"
}
