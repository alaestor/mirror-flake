{ inputs, pkgs, system }:
let
  fixture = inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [
      ../nucleus/flake-module.nix
      ../modules/features/memory-manager.nix
    ];
  };

  mkConfig =
    overrides:
    (inputs.unstable-nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        fixture.modules.nixos.memory-manager
        { system.stateVersion = "24.11"; }
        overrides
      ];
    }).config;

  defaults = mkConfig { };
  quiet = mkConfig { memory-manager.zram.enable = false; memory-manager.earlyoom.enable = false; };
  oomdHost = mkConfig { systemd.oomd.enable = true; };

  assertions = [
    {
      assertion = defaults.zramSwap.enable && defaults.zramSwap.memoryPercent == 30;
      message = "memory-manager did not provide compressed swap by default";
    }
    {
      assertion = defaults.services.earlyoom.enable;
      message = "memory-manager did not enable the userspace OOM killer by default";
    }
    {
      assertion = !defaults.services.earlyoom.enableNotifications;
      message = "memory-manager announced kills on D-Bus without being asked to";
    }
    {
      assertion = !defaults.systemd.oomd.enable;
      message = "memory-manager left systemd-oomd racing earlyoom over the same pressure";
    }
    {
      assertion = !quiet.zramSwap.enable && !quiet.services.earlyoom.enable;
      message = "memory-manager halves are not independently switchable";
    }
    {
      assertion = oomdHost.systemd.oomd.enable;
      message = "memory-manager forced systemd-oomd off rather than defaulting it off";
    }
  ];

  failures = map (result: result.message) (
    builtins.filter (result: !result.assertion) assertions
  );
in
pkgs.runCommand "memory-manager-test"
  {
    passAsFile = [ "failureReport" ];
    failureReport = builtins.concatStringsSep "\n" failures;
  }
  ''
    if [[ -s "$failureReportPath" ]]; then
      echo "memory-manager assertions failed:" >&2
      sed 's/^/- /' "$failureReportPath" >&2
      exit 1
    fi
    touch "$out"
  ''
