{ inputs, pkgs, system, ... }:
let
  lib = inputs.nixpkgs.lib;
  cfg = (lib.nixosSystem {
    inherit system;
    modules = [ inputs.self.modules.nixos.global-config ];
  }).config;
  logs = inputs.self.fleet.logging;
  journal = cfg.services.journald.settings.Journal;
  collector = (lib.nixosSystem {
    inherit system;
    modules = [ inputs.self.modules.nixos.telemetry-server { telemetry-server.enable = true; } ];
  }).config;
in
assert journal.MaxRetentionSec == "${toString logs.retentionDays}day";
assert journal.MaxFileSec == "${toString logs.journalRotationDays}day";
assert journal.SystemMaxUse == logs.journalMaxUse;
assert journal.RuntimeMaxUse == logs.runtimeJournalMaxUse;
assert collector.services.loki.configuration.limits_config.retention_period == "${toString (24 * logs.retentionDays)}h";
pkgs.testers.runNixOSTest {
  name = "log-retention";
  node.pkgsReadOnly = false;
  nodes.machine = { pkgs, ... }: {
    imports = [ inputs.self.modules.nixos.global-config ];
    environment.systemPackages = [ pkgs.python3 ];
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    with subtest("the installed journal policy has age, rotation, and size limits"):
        machine.succeed("systemd-analyze cat-config systemd/journald.conf > /tmp/journal-config")
        for setting in ["SystemMaxUse=${logs.journalMaxUse}", "RuntimeMaxUse=${logs.runtimeJournalMaxUse}", "MaxRetentionSec=${toString logs.retentionDays}day", "MaxFileSec=${toString logs.journalRotationDays}day"]:
            machine.succeed(f"grep -Fx '{setting}' /tmp/journal-config")
    with subtest("a real crash records an event but leaves no memory image"):
        machine.succeed("systemd-analyze cat-config systemd/coredump.conf | grep -Fx Storage=none")
        machine.succeed("systemd-analyze cat-config systemd/coredump.conf | grep -Fx ProcessSizeMax=0")
        machine.fail("systemd-run --unit=crash-fixture --wait --property=LimitCORE=infinity python -c 'import os; os.abort()'")
        machine.wait_until_succeeds("journalctl -b --no-pager | grep -F 'crash-fixture.service: Main process exited'")
        machine.wait_until_succeeds("test -z \"$(systemctl list-units 'systemd-coredump@*.service' --state=running --no-legend)\"")
        machine.succeed("test -z \"$(ls -A /var/lib/systemd/coredump)\"")
  '';
}
