{ lib, pkgs, ... }:
{
  users.groups.apc-mouse-remap = { };
  users.users.apc-mouse-remap = {
    isSystemUser = true;
    group = "apc-mouse-remap";
  };
  # Match the receiver interface already selected by the by-id input path.
  # No input-group membership: other keyboards remain inaccessible.
  services.udev.extraRules = ''
    SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_VENDOR_ID}=="046d", ENV{ID_MODEL_ID}=="c547", ENV{ID_USB_INTERFACE_NUM}=="02", ENV{ID_INPUT_MOUSE}=="1", GROUP="apc-mouse-remap", MODE="0660"
    SUBSYSTEM=="misc", KERNEL=="uinput", GROUP="apc-mouse-remap", MODE="0660"
  '';
  # G502 X Lightspeed buttons, verified with evtest on this receiver:
  # front/rear beside left-click and sniper. Other inputs pass through.
  boot.kernelModules = [ "uinput" ];
  systemd.services.apc-mouse-remap = {
    description = "Map G502 X extra buttons to numpad +, -, *";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udevd.service" ];
    startLimitIntervalSec = 0;
    serviceConfig = {
      User = "apc-mouse-remap";
      Group = "apc-mouse-remap";
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
      AmbientCapabilities = "";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateNetwork = true;
      RestrictAddressFamilies = [ "AF_UNIX" ];
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      DevicePolicy = "closed";
      # Input minors change on hotplug. DAC above limits this account to
      # the receiver even though the cgroup permits the input major.
      DeviceAllow = [ "char-input rw" "/dev/uinput rw" ];
      ExecStart = lib.escapeShellArgs [
        "${pkgs.evsieve}/bin/evsieve"
        "--input"
        "/dev/input/by-id/usb-Logitech_USB_Receiver-if02-event-mouse"
        "grab"
        "persist=reopen"
        "--map"
        "btn:forward"
        "key:kpplus"
        "--map"
        "btn:back"
        "key:kpminus"
        "--map"
        "btn:task"
        "key:kpasterisk"
        "--output"
        "key:kpplus"
        "key:kpminus"
        "key:kpasterisk"
        "name=APC G502 X numpad keys"
        "repeat"
        "--output"
        "name=APC G502 X mouse"
      ];
      # Retry if the receiver is absent at boot; reopen it after unplugging.
      Restart = "always";
      RestartSec = "5s";
    };
  };

}
