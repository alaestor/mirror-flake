{ inputs, pkgs, ... }:
pkgs.testers.runNixOSTest {
  name = "telemetry-runtime";
  nodes = {
    collector = { pkgs, ... }: {
      imports = [ inputs.self.modules.nixos.telemetry-server ];
      telemetry-server = {
        enable = true;
        publicUrl = "http://collector:3030/";
        clients = [ "sender" ];
        alerts = {
          spamThreshold = 10;
          ignoredPatterns = [ "telemetry-known-noise" ];
        };
      };
      # VLAN 1 stands in for the trusted tunnel. VLAN 2 is the hostile LAN.
      virtualisation.vlans = [
        1
        2
      ];
      virtualisation.memorySize = 4096;
      telemetry.interface = "eth1";
      environment.systemPackages = [
        pkgs.curl
        pkgs.jq
      ];
    };
    sender = { pkgs, ... }: {
      imports = [ inputs.self.modules.nixos.telemetry ];
      telemetry = {
        enable = true;
        interface = "eth1";
        pushUrl = "http://collector:3100/loki/api/v1/push";
      };
      virtualisation.vlans = [ 1 ];
      environment.systemPackages = [ pkgs.curl ];
    };
    outsider = { pkgs, ... }: {
      imports = [ inputs.self.modules.nixos.telemetry ];
      telemetry = {
        enable = true;
        interface = "late0";
        pushUrl = "http://127.0.0.1:1/loki/api/v1/push";
      };
      virtualisation.vlans = [ 2 ];
      environment.systemPackages = [ pkgs.curl ];
    };
  };
  testScript =
    builtins.readFile ./telemetry/runtime.py + builtins.readFile ./telemetry/outage-replay.py;
}
