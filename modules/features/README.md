## global-config

Global configurations included automatically when using lib's `mk...` helpers

## isolive

Creates a minimal NixOS installer ISO file no grub countdown or `wpa_supplicant`.

Use `networking.wireless.enable = lib.mkForce true;` if you want to re-enable `wpa_supplicant`
