{ lib, ... }:
{
  programs.plasma = {
    # WARN(SECURITY): weakens physical security posture
    # Idle/resume locking remains mutable and is currently disabled on APC.
    # Physical access is outside this workstation's threat model.
    input.mice = lib.mkAfter [
      {
        enable = true;
        name = "Logitech, Inc. USB Receiver";
        acceleration = 0.0;
        accelerationProfile = "none";
        naturalScroll = false;
        scrollSpeed = 1;
        leftHanded = false;
        middleButtonEmulation = false;
        vendorId = "046d";
        productId = "c547";
      }
      {
        # Virtual mouse created by the apc-mouse-remap evsieve service.
        enable = true;
        name = "APC G502 X mouse";
        acceleration = 0.0;
        accelerationProfile = "none";
        naturalScroll = false;
        scrollSpeed = 1;
        leftHanded = false;
        middleButtonEmulation = false;
        vendorId = "0000";
        productId = "0000";
      }
    ];

    configFile."kcminputrc"."Mouse"."XLbInptPointerAcceleration" = 0;
  };
}
