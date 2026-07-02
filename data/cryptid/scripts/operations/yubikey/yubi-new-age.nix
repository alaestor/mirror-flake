{ context }:
with context;
# TODO(crypt): age: both keys must use an identical schema; the YubiKey plugin does not support PQ yet, so both keys need to be raw.
# TODO(crypt): age: add a post-quantum YubiKey resident key once https://github.com/str4d/age-plugin-yubikey/issues/217 is resolved.
# TODO(quality): pass the PIN by environment variable once https://github.com/str4d/age-plugin-yubikey/issues/20 is resolved.
{
  name = "yubi-new-age";
  description = "create a resident age key on the YubiKey";
  category = "lesser";
  wrapped = true;
  hidden = false;
  content = ''
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
  '';
}
