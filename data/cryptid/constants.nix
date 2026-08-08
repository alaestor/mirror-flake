rec {
  version = "0.1.0-20260620";

  persist-partition-label = "PERSIST";
  path-mount-persist = "/persist";
  vault-name = ".VAULT";
  path-vault-file = "${path-mount-persist}/${vault-name}";
  path-mount-vault = "/vault";

  vault-fs = "FAT";
  vault-size = "300K";
  vault-hasher = "sha512";
  vault-crypto = "AES-Twofish";
  vault-pim = "0";

  pgp-expiry-in-months = "13";
  pgp-rootkey-type = "eddsa";
  pgp-rootkey-curve = "ed25519";
  pgp-preferences = "SHA512 AES256 ZLIB BZIP2 ZIP Uncompressed";
  pgp-sign-algorithm = "ed25519";
  pgp-encrypt-algorithm = "cv25519";

  yubi-retries-pin = "5";
  yubi-retries-puk = "5";
  yubi-retries-admin = "5";
  yubi-touch-policy = "on";
  yubi-pass-policy = "once";
  yubi-age-pass-policy = "once";
  yubi-age-touch-policy = "always";
  yubi-age-piv-slot = "1";
  yubi-stock-pgp-pin = "123456";
  yubi-stock-pgp-admin = "12345678";
  yubi-stock-piv-pin = yubi-stock-pgp-pin;
  yubi-stock-piv-puk = yubi-stock-pgp-admin;
  yubi-stock-piv-mgt = "010203040506070801020304050607080102030405060708";
  # TODO(crypt): switch back to AES192 when age-plugin-yubikey supports it.
  yubi-piv-management-alg = "TDES";

  path-firsttimeflag = "/tmp/first-time-init";
  path-log-expectScript = "./expectScript.log";

  pathv-yubicodes = "${path-mount-vault}/yubicodes/yubicodes.env";
  pathv-pgp-private = "${path-mount-vault}/pgp/pgp.key.asc";
  pathv-pgp-public = "${path-mount-persist}/pgp-cert/pgp.certificate.asc";
  pathv-pgp-revoke = "${path-mount-persist}/pgp-revoke/pgp.revocation.asc";
  pathv-ssh-public = "${path-mount-persist}/sk-public/ssh_sk.pub";
  pathv-ssh-stub = "${path-mount-persist}/sk-stub/ssh_sk";
  pathv-age-public = "${path-mount-persist}/sk-public/age_sk.pub";
  pathv-age-stub = "${path-mount-persist}/sk-stub/age_sk";
  pathv-merged-pubs-ssh = "${path-mount-persist}/merged-ssh/authorized_keys";
  pathv-merged-pubs-age = "${path-mount-persist}/merged-age/recipients.txt";
  emergency-label-ssh = "cryptid-breakglass-ssh";
  emergency-label-age = "cryptid-breakglass-age";
  emergency-filename = name: "breakglass-${name}";
  emergency-filename-ssh = emergency-filename "ssh";
  pathv-emerg-ssh-private = "${path-mount-vault}/breakglass/${emergency-filename-ssh}";
  pathv-emerg-ssh-public = "${path-mount-persist}/breakglass/${emergency-filename-ssh}.pub";
  emergency-filename-age = emergency-filename "age";
  pathv-emerg-age-private = "${path-mount-vault}/breakglass/${emergency-filename-age}";
  pathv-emerg-age-public = "${path-mount-persist}/breakglass/${emergency-filename-age}.pub";

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

  env = {
    keyid = "KEYID";
    name = "USER_NAME";
    email = "USER_EMAIL";
    vaultpass = "VAULTPASS";
    yubi = {
      serial = "YUBI_SERIAL";
      fido.pin = "YUBI_FIDO_PIN";
      piv = { pin = "YUBI_PIV_PIN"; puk = "YUBI_PIV_PUK"; };
      pgp = { pin = "YUBI_PGP_PIN"; reset = "YUBI_PGP_RESET"; admin = "YUBI_PGP_ADMIN"; };
    };
  };
}
