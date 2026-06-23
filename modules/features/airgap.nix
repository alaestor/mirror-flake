{
  flake.modules.nixos.airgap = { lib, ... } : {
    boot.initrd.network.enable = lib.mkForce false;
    boot.blacklistedKernelModules = [
      "iwlwifi"
      "iwlmvm"
      "cfg80211"
      "mac80211"
      "igc"
      "btusb"
      "btrtl"
      "btintel"
      "btbcm"
      "btmtk"
      "bluetooth"
    ];
    services.blueman.enable    = lib.mkForce false;
    hardware.bluetooth.enable  = lib.mkForce false;
    networking = {
      firewall = {
        enable                 = lib.mkForce true;
        rejectPackets          = lib.mkForce true;
      };
      interfaces               = lib.mkForce {};
      resolvconf.enable        = lib.mkForce false;
      useNetworkd              = lib.mkForce false;
      useDHCP                  = lib.mkForce false;
      dhcpcd.enable            = lib.mkForce false;
      wireless.enable          = lib.mkForce false;
      networkmanager.enable    = lib.mkForce false;
    };
    systemd.services = {
      NetworkManager.enable    = lib.mkForce false;
      systemd-networkd.enable  = lib.mkForce false;
    };
  };
}
