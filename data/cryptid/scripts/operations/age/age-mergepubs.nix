{ context }:
with context;
{
  name = "age-mergepubs";
  description = "yubi+breakglass -> 'recipients.txt'";
  category = "lesser";
  wrapped = true;
  hidden = false;
  content = ''
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
  '';
}
