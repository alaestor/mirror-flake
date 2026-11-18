{ inputs, pkgs, system, ... }:
let
  lib = inputs.nixpkgs.lib;
  evaluate = overrides: (lib.nixosSystem {
    inherit system;
    modules = [
      inputs.self.modules.nixos.global-config
      inputs.self.modules.nixos.telemetry
      { telemetry.enable = true; }
      overrides
    ];
  }).config;
  defaults = evaluate { };
  managed = evaluate { networking.networkmanager.enable = true; };
  dualStack = evaluate { networking.enableIPv6 = true; };
  socket = c: c.systemd.sockets.telemetry-metrics.socketConfig;
  checks = [
    {
      assertion = builtins.all (c:
        !c.networking.enableIPv6
        && lib.elem "ipv6.disable=1" c.boot.kernelParams
      ) [ defaults managed ];
      message = "Fleet defaults must disable the IPv6 stack, including with NetworkManager";
    }
    {
      assertion = (socket defaults).ListenStream == "0.0.0.0:9100"
        && !((socket defaults) ? BindIPv6Only)
        && (socket defaults).BindToDevice == "tailscale0"
        && defaults.networking.firewall.allowedTCPPorts == [ ]
        && defaults.networking.firewall.interfaces.tailscale0.allowedTCPPorts == [ 9100 ];
      message = "IPv4 telemetry must preserve device binding and private ingress without an IPv6 socket";
    }
    {
      assertion = dualStack.networking.enableIPv6
        && !(lib.elem "ipv6.disable=1" dualStack.boot.kernelParams)
        && (socket dualStack).ListenStream == "[::]:9100"
        && (socket dualStack).BindIPv6Only == "both"
        && (socket dualStack).BindToDevice == "tailscale0";
      message = "An explicit dual-stack exception must omit the disable argument and retain dual-stack telemetry";
    }
  ];
  failures = map (check: check.message) (builtins.filter (check: !check.assertion) checks);
in
pkgs.runCommand "ipv4-only-policy-test" {
  passAsFile = [ "failureReport" ];
  failureReport = lib.concatStringsSep "\n" failures;
} ''
  if [[ -s "$failureReportPath" ]]; then
    cat "$failureReportPath" >&2
    exit 1
  fi
  touch "$out"
''
