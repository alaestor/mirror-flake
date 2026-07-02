{ context }:
with context;
{
  name = "yubi-reset";
  description = "reset the YubiKey to factory defaults";
  category = "lesser";
  wrapped = true;
  hidden = false;
  content = ''
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
  '';
}
