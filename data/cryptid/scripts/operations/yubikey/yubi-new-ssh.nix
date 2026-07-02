{ context }:
with context;
{
  name = "yubi-new-ssh";
  description = "create a resident ssh key on the YubiKey";
  category = "lesser";
  wrapped = true;
  hidden = false;
  content = ''
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
  '';
}
