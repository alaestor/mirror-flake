{ inputs, pkgs, ... }:
let
  probe = pkgs.runCommandCC "dufs-apparmor-probe" {
    buildInputs = [ pkgs.libapparmor ];
  } ''
    mkdir -p "$out/bin"
    $CC -Wall -Wextra -Werror ${./dufs/apparmor_probe.c} -lapparmor -o "$out/bin/probe"
  '';
in
pkgs.testers.runNixOSTest {
  name = "dufs-apparmor";
  nodes.machine = { lib, pkgs, ... }: {
    imports = [ inputs.self.modules.nixos.serve-dufs ];
    serve.dufs = {
      enable = true;
      authFile = "/run/dufs-auth.env";
      shares.Films = "/srv/films";
    };
    # Start deliberately after selecting complain mode for the first pass.
    systemd.services.dufs.wantedBy = lib.mkForce [ ];
    environment.systemPackages = [ pkgs.apparmor-parser pkgs.curl pkgs.openssl pkgs.python3 probe ];
    systemd.tmpfiles.rules = [
      "d /srv/films/Album 0755 root root -"
      "f /srv/films/Album/Track.txt 0444 root root - fixture-track"
      "d /media/Films 0755 root root -"
      "f /media/Films/allowed 0666 root root - readable-fixture"
      "f /tmp/dufs-forbidden 0666 root root - forbidden-fixture"
    ];
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("apparmor.service")
    machine.succeed("test $(cat /sys/module/apparmor/parameters/enabled) = Y")
    machine.succeed("printf \"DUFS_AUTH='fixture:%s@/:ro'\\n\" \"$(printf fixture-password | openssl passwd -6 -stdin)\" > /run/dufs-auth.env; chmod 600 /run/dufs-auth.env")
    machine.succeed("cp /run/dufs-auth.env /run/dufs-auth.valid")

    with subtest("review normal operations in complain mode before enforcement"):
        machine.succeed("apparmor_parser -C -r /etc/apparmor.d/serve-dufs")
        machine.succeed("systemctl start dufs")
        machine.wait_for_open_port(8087)
        machine.succeed("python ${./dufs/apparmor_http.py}")
        machine.succeed("journalctl -k -o cat > /tmp/complain-audit")
        machine.fail("grep -E 'apparmor=\"ALLOWED\".*profile=\"serve-dufs' /tmp/complain-audit")

    with subtest("the actual daemon runs confined and serves authenticated workflows"):
        machine.succeed("apparmor_parser -r /etc/apparmor.d/serve-dufs; systemctl restart dufs")
        machine.wait_for_open_port(8087)
        machine.succeed("test \"$(cat /proc/$(systemctl show dufs -p MainPID --value)/attr/current)\" = 'serve-dufs (enforce)'")
        machine.succeed("grep -E '^NoNewPrivs:[[:space:]]+1$' /proc/$(systemctl show dufs -p MainPID --value)/status")
        machine.succeed("python ${./dufs/apparmor_http.py}")
        machine.succeed("journalctl -k -o cat > /tmp/enforce-audit")
        machine.fail("grep -E 'apparmor=\"DENIED\".*profile=\"serve-dufs' /tmp/enforce-audit")

    with subtest("AppArmor independently denies reads, writes and unrelated execution"):
        # No systemd sandbox here: the fixture is DAC-readable/writable. These
        # failures must be EACCES from AppArmor, not a read-only mount or chroot.
        machine.succeed("runuser -u dufs -- cat /media/Films/allowed /tmp/dufs-forbidden")
        # If execution unexpectedly succeeds, false exits nonzero rather than
        # letting the probe appear successful by replacing itself with true.
        machine.succeed("runuser -u dufs -- ${probe}/bin/probe ${pkgs.coreutils}/bin/false")
        machine.succeed("journalctl -k -o cat | grep -E 'apparmor=\"DENIED\".*profile=\"serve-dufs\"'")

    with subtest("authentication guard still fails closed under confinement"):
        machine.succeed("systemctl stop dufs; printf 'DUFS_AUTH=\\n' > /run/dufs-auth.env")
        machine.fail("systemctl start dufs")
        machine.succeed("systemctl stop dufs")
        machine.succeed("journalctl -u dufs -o cat | grep -F 'Dufs requires DUFS_AUTH'")

    with subtest("a missing profile fails startup rather than running unconfined"):
        machine.succeed("cp /run/dufs-auth.valid /run/dufs-auth.env")
        machine.succeed("apparmor_parser -R /etc/apparmor.d/serve-dufs")
        machine.fail("systemctl start dufs")
        machine.succeed("systemctl stop dufs")
        machine.succeed("test $(systemctl show dufs -p MainPID --value) = 0")
        machine.succeed("journalctl -u dufs -o cat | grep -F 'APPARMOR'")
  '';
}
