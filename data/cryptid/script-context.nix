{ constants, username }:
with constants;
rec {
  inherit username;

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
    export GNUPGHOME=/run/user/$(id -u)/gnupghome
    if [ ! -d "$GNUPGHOME" ]; then
      mkdir "$GNUPGHOME"
      chmod 700 "$GNUPGHOME"
    fi
    # ssh-keygen's ccid use can require reinserting the device.
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

  expect-error-cases = ''eof { puts "Error: unexpected EOF"; exit 3 } timeout { puts "Error: timeout"; exit 2 }'';
  expect-default-spawn = ''if {\$spawn eq ""} { set spawn \$::spawn_id }'';
  expect-header = ''
    set default_timeout_value 5
    set timeout \$default_timeout_value
    proc safe_expect { pattern {spawn ""} } {
      ${expect-default-spawn}
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
    # Returns the number of 'ssb' subkeys listed by gpg.
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
}
