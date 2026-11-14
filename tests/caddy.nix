{ inputs, pkgs, ... }:
let
  # Reuse nixpkgs' disposable ACME endpoint certificate, never a real CA/key.
  certs = import "${inputs.nixpkgs}/nixos/tests/common/acme/server/snakeoil-certs.nix";
  pebbleConfig = pkgs.writeText "caddy-pebble.json" (builtins.toJSON {
    pebble = {
      listenAddress = "127.0.0.1:14000";
      managementListenAddress = "127.0.0.1:15000";
      certificate = certs.${certs.domain}.cert;
      privateKey = certs.${certs.domain}.key;
      httpPort = 80;
      tlsPort = 443;
      profiles.default = {
        description = "Short-lived sandbox test certificate";
        validityPeriod = 60;
      };
    };
  });
in
pkgs.testers.runNixOSTest {
  name = "caddy";
  nodes.machine = { config, pkgs, ... }: {
    imports = [ inputs.self.modules.nixos.serve-caddy ];
    serve.caddy.enable = true;
    virtualisation.memorySize = 2048;
    environment.systemPackages = [ pkgs.curl pkgs.openssl ];
    networking.hosts."127.0.0.1" = [ "fixture.test" "reload.test" certs.domain ];
    security.pki.certificateFiles = [ certs.ca.cert ];
    services.caddy = {
      acmeCA = "https://${certs.domain}:14000/dir";
      globalConfig = ''
        renew_interval 1s
        renewal_window_ratio 0.5
      '';
      virtualHosts."fixture.test".extraConfig = ''
        handle /proxy {
          reverse_proxy 127.0.0.1:8080
        }
        handle_path /.cerberus/* {
          cerberus_endpoint
        }
        @challenge path /protected
        cerberus @challenge {
          base_url "/.cerberus"
        }
        handle {
          root * /mnt/sites/fixture
          file_server
        }
        log {
          output file /var/log/caddy/fixture.log
        }
      '';
    };
    specialisation.reload.configuration.services.caddy.virtualHosts."http://reload.test".extraConfig = ''
      respond "reloaded"
    '';
    systemd.tmpfiles.rules = [
      "d /mnt/sites/fixture 0755 root root -"
      "f /mnt/sites/fixture/index.html 0444 root root - static-fixture"
      "f /mnt/sites/fixture/protected 0444 root root - protected-fixture"
      "d /mnt/unrelated 0755 root root -"
      "f /mnt/unrelated/private 0444 root root - unrelated-fixture"
      "d /var/lib/caddy-denied 0777 root root -"
      "f /var/lib/caddy-denied/readable 0444 root root - readable-fixture"
      "L /mnt/sites/fixture/escape - - - - /mnt/unrelated/private"
    ];
    systemd.services = {
      pebble = {
        wantedBy = [ "multi-user.target" ];
        environment = {
          PEBBLE_VA_NOSLEEP = "1";
          PEBBLE_WFE_NONCEREJECT = "0";
        };
        serviceConfig.ExecStart = "${pkgs.pebble}/bin/pebble -config ${pebbleConfig}";
      };
      fixture-backend = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          DynamicUser = true;
          ExecStart = "${pkgs.python3}/bin/python -m http.server 8080 --bind 127.0.0.1 --directory ${pkgs.writeTextDir "proxy" "proxy-fixture"}";
        };
      };
      caddy = {
        after = [ "pebble.service" ];
        # Model Lanser's NAS boundary with a single static-content root.
        serviceConfig = {
          TemporaryFileSystem = [ "/mnt:ro" ];
          BindReadOnlyPaths = [ "/mnt/sites/fixture" ];
        };
      };
      caddy-probe = {
        requires = [ "caddy.service" ];
        after = [ "caddy.service" ];
        serviceConfig = (builtins.removeAttrs config.systemd.services.caddy.serviceConfig [
          "ExecStart" "ExecReload" "Restart" "RestartSec" "RestartPreventExitStatus"
          # The probe must not manage the real service's socket lifetime.
          "RuntimeDirectory" "RuntimeDirectoryMode"
        ]) // {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "caddy-sandbox-probe" ''
            set -eu
            must_deny() {
              if "$@" >/dev/null 2>&1; then
                echo "Sandbox unexpectedly allowed: $*" >&2
                exit 1
              fi
            }
            test "$(id -un)" = caddy
            test -r /etc/caddy/caddy_config
            test -r /mnt/sites/fixture/index.html
            test -r /var/lib/caddy-denied/readable
            touch /var/lib/caddy/probe-state
            touch /var/log/caddy/probe-log
            touch /run/caddy/probe-runtime
            touch /tmp/caddy-private
            test ! -e /tmp/host-private
            must_deny touch /var/lib/caddy-denied/write
            must_deny touch /run/caddy-unexpected-write
            must_deny touch /mnt/sites/fixture/write
            must_deny cat /mnt/unrelated/private
            must_deny cat /mnt/sites/fixture/escape
            test ! -e /dev/kmsg
          '';
        };
      };
    };
  };
  testScript = { nodes, ... }: ''
    machine.start()
    machine.wait_for_unit("pebble.service")
    machine.wait_for_unit("caddy.service")
    machine.wait_for_unit("fixture-backend.service")
    machine.succeed("curl -fsS https://${certs.domain}:15000/roots/0 > /tmp/pebble-root.pem")
    https = "curl -fsS --cacert /tmp/pebble-root.pem https://fixture.test"
    serial = "echo | openssl s_client -connect 127.0.0.1:443 -servername fixture.test 2>/dev/null | openssl x509 -noout -serial"

    def check_admin_boundary():
        machine.succeed("test $(stat -c %a /run/caddy) = 700 && test $(stat -c %a /run/caddy/admin.sock) = 600")
        machine.succeed("runuser -u caddy -- curl -fsS --unix-socket /run/caddy/admin.sock http://localhost/config/ > /dev/null")
        machine.fail("runuser -u nobody -- curl -fsS --max-time 2 --unix-socket /run/caddy/admin.sock http://localhost/config/")
        machine.succeed("test -z \"$(ss -H -ltn 'sport = :2019')\"")
        machine.fail("curl --noproxy '*' -fsS --max-time 2 http://127.0.0.1:2019/config/")
        machine.fail("curl --noproxy '*' -g -fsS --max-time 2 http://[::1]:2019/config/")

    with subtest("admin API is available to Caddy but not other local users or TCP clients"):
        check_admin_boundary()

    with subtest("ACME issuance, static content, proxying, and Cerberus"):
        machine.wait_until_succeeds(https + "/ | grep -Fx static-fixture")
        machine.succeed(https + "/proxy | grep -Fx proxy-fixture")
        machine.fail(https + "/escape")
        machine.succeed(https + "/protected > /tmp/challenge; grep -F 'Cerberus' /tmp/challenge")
        machine.fail("grep -Fx protected-fixture /tmp/challenge")
        machine.succeed("test -s /var/log/caddy/fixture.log")
        # Verify the real process, including the packaged unit's inherited caps.
        pid = machine.succeed("systemctl show caddy -p MainPID --value").strip()
        machine.succeed(f"test $(grep -Ec '^Cap(Amb|Bnd):[[:space:]]+0000000000000400$' /proc/{pid}/status) = 2")

    with subtest("sandbox permits state and logs, denies unrelated writes and NAS reads"):
        machine.succeed("touch /tmp/host-private; systemctl start caddy-probe")
        machine.succeed("test -e /var/lib/caddy/probe-state; test -e /var/log/caddy/probe-log; test ! -e /tmp/caddy-private")

    with subtest("automatic certificate renewal without restarting Caddy"):
        before = machine.succeed(serial).strip()
        assert before.startswith("serial=")
        machine.wait_until_succeeds(f"current=$({serial}); test -n \"$current\" && test \"$current\" != '{before}'", timeout=120)
        machine.succeed(https + "/ | grep -Fx static-fixture")
        assert machine.succeed("systemctl show caddy -p MainPID --value").strip() == pid

    with subtest("NixOS reload applies changed routes without restarting"):
        machine.succeed("${nodes.machine.system.build.toplevel}/specialisation/reload/bin/switch-to-configuration test >&2")
        machine.succeed("curl -fsS http://reload.test | grep -Fx reloaded")
        machine.succeed(https + "/proxy | grep -Fx proxy-fixture")
        assert machine.succeed("systemctl show caddy -p MainPID --value").strip() == pid
        check_admin_boundary()

    with subtest("restart recreates the private admin socket"):
        machine.succeed("systemctl restart caddy")
        machine.wait_until_succeeds(https + "/proxy | grep -Fx proxy-fixture")
        check_admin_boundary()
  '';
}
