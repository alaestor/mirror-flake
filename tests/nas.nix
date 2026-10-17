{ inputs, pkgs, system, ... }:
let
  lib = inputs.nixpkgs.lib;
  evaluate = overrides: (lib.nixosSystem {
    inherit system;
    modules = [
      inputs.self.modules.nixos.nas
      inputs.self.modules.nixos.user-environment
      {
        networking.interfaces.storage.ipv4.addresses = [
          { address = "192.0.2.1"; prefixLength = 24; }
        ];
      }
      overrides
    ];
  }).config;
  scripted = evaluate { nas.pocket.enable = true; };
  networkd = evaluate {
    nas.pocket.enable = true;
    networking.useNetworkd = true;
  };
  disabled = evaluate { };
  addressUnit = "network-addresses-storage.service";
  afterNetwork = config: config.systemd.targets.network.after or [ ];
  failures = lib.concatLists [
    (lib.optional (!(lib.elem addressUnit (afterNetwork scripted)))
      "NAS must keep scripted addresses until network.target stops")
    (lib.optional (lib.elem addressUnit (afterNetwork networkd))
      "NAS must not reference scripted address units with networkd")
    (lib.optional (lib.elem addressUnit (afterNetwork disabled))
      "Disabled NAS must not change network teardown ordering")
    (lib.optional (lib.elem addressUnit scripted.systemd.targets.network.wants)
      "NAS ordering must not pull in optional interface address units")
    (lib.optional (!(lib.elem "mnt-Pocket.mount" scripted.systemd.services.nas-detach.after))
      "NAS detach must stop before the share is unmounted")
  ];
in
pkgs.runCommand "nas-test" {
  passAsFile = [ "failureReport" ];
  failureReport = lib.concatStringsSep "\n" failures;
} ''
  if [[ -s "$failureReportPath" ]]; then
    cat "$failureReportPath" >&2
    exit 1
  fi
  touch "$out"
''
