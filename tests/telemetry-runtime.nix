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
      # Exercise priority-derived metadata in native patterns without adopting
      # the experimental ingester in production configuration.
      services.loki.extraFlags = [ "-pattern-ingester.enabled=true" ];
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
        # Test missing/invalid source fields through the production stages.
        extraConfig = ''
          loki.source.api "metadata_fixtures" {
            http {
              listen_address = "127.0.0.1"
              listen_port = 12346
            }
            forward_to = [loki.process.journal.receiver]
          }
        '';
      };
      users.users.fixture = {
        isNormalUser = true;
        uid = 1000;
        linger = true;
      };
      systemd.user.services.telemetry-user-fixture = {
        wantedBy = [ "default.target" ];
        serviceConfig = {
          Type = "simple";
          SyslogIdentifier = "telemetry-user-fixture";
        };
        # Keep the cgroup alive while journald resolves trusted unit fields.
        script = ''
          echo "<4>telemetry-user-metadata"
          exec sleep infinity
        '';
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
