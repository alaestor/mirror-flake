{ context }:
with context;
{
  name = "gpg-new-rootkey";
  description = "create a new root key";
  category = "lesser";
  wrapped = true;
  hidden = false;
  content = ''
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
  '';
}
