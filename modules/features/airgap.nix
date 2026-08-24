/**
  Disables every network-facing service and driver class this repository
  knows how to name, for a host that must never come up on a network.

  This is best-effort, not a hard isolation guarantee: the
  `blacklistedKernelModules` list names specific drivers (`iwlwifi`, an Intel
  Wi-Fi chipset; `igc`, an Intel 2.5G Ethernet chipset; several Bluetooth
  drivers), not device classes, so it is only as complete as this list is for
  whatever hardware the host actually has. The `networking.*` overrides
  (`interfaces = mkForce {}`, no DHCP client, no NetworkManager, no
  networkd) are the real, hardware-independent guarantee — they mean an
  unlisted interface comes up without an address rather than not at all.
  Currently imported by exactly one host, `cryptid`
  (`hosts/cryptid/scripts.nix`), whose ISO must handle arbitrary hardware; if
  this module gains a second consumer with different hardware, audit the
  blacklist against that hardware before trusting it.
*/
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
