{ lib, ... }:
{
  programs.plasma = {
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
    ];

    configFile."kcminputrc"."Mouse"."XLbInptPointerAcceleration" = 0;
  };
}
