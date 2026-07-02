{ context }:
with context;
{
  name = "yubi-move-keys";
  description = "move the two pgp subkeys to the YubiKey";
  category = "lesser";
  wrapped = true;
  hidden = false;
  content = ''
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
  '';
}
