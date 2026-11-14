{ inputs, pkgs, ... }:
let
  node = externalSecret: { config, lib, pkgs, ... }: {
    imports = [ inputs.self.modules.nixos.serve-headscale ];
    serve.headscale = {
      enable = true;
    } // lib.optionalAttrs externalSecret {
      cookieSecretFile = "/run/headplane-fixture-cookie";
    };
    services.headscale.settings = {
      server_url = "http://127.0.0.1:8092";
      # Keep the fixture independent of public DNS and relay-map downloads.
      derp = {
        urls = [ ];
        server = {
          enabled = true;
          region_id = 999;
          stun_listen_addr = "127.0.0.1:3478";
        };
      };
    };
    services.headplane.settings.server.cookie_secure = false;
    environment.systemPackages = [ pkgs.curl pkgs.jq ];
    virtualisation.memorySize = 2048;

    # Model Lanser's host-owned NAS hiding without depending on a real NAS.
    systemd.services.headplane.serviceConfig.TemporaryFileSystem = [ "/mnt:ro" ];
    systemd.tmpfiles.rules = [
      "d /mnt/unrelated 0755 root root -"
      "f /mnt/unrelated/private 0444 root root - fixture-nas-data"
      "d /var/lib/headplane-denied 0777 root root -"
    ] ++ lib.optional externalSecret
      "f /run/headplane-fixture-cookie 0400 root root - 01234567890123456789012345678901";

    # Exercise the same sandbox as the application with explicit allowed and
    # forbidden operations. This avoids treating unit-property assertions as
    # proof that the kernel actually enforced them.
    systemd.services.headplane-probe = lib.mkIf externalSecret {
      requires = [ "headplane.service" ];
      after = [ "headplane.service" ];
      serviceConfig = (builtins.removeAttrs config.systemd.services.headplane.serviceConfig [
        "ExecStart" "ExecStartPre" "Restart" "RestartSec"
      ]) // {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "headplane-sandbox-probe" ''
          set -eu
          must_deny() {
            if "$@" >/dev/null 2>&1; then
              echo "Sandbox unexpectedly allowed: $*" >&2
              exit 1
            fi
          }
          test "$(id -un)" = headplane
          test "$(id -gn)" = headplane
          test -r ${config.services.headscale.configFile}
          test -r "$CREDENTIALS_DIRECTORY/cookie-secret"
          touch /var/lib/headplane/probe-state
          touch /tmp/headplane-private
          test ! -e /tmp/host-private
          must_deny cat /run/headplane-fixture-cookie
          must_deny cat /var/lib/headscale/noise_private.key
          must_deny cat /mnt/unrelated/private
          must_deny touch /var/lib/headplane-denied/write
          must_deny touch /run/headplane-unexpected-write
          must_deny touch /etc/headplane-unexpected-write
          must_deny kill -0 "$(cat /run/headplane-probe.pid)"
          test ! -e /dev/kmsg
        '';
      };
    };
  };
in
pkgs.testers.runNixOSTest {
  name = "headplane";
  nodes.machine = node true;
  nodes.generated = node false;
  testScript = ''
    start_all()
    for host in [machine, generated]:
        host.wait_for_unit("headscale.service")
        host.wait_for_unit("headplane.service")
        host.wait_until_succeeds("curl -fsS http://127.0.0.1:3000/admin/login > /dev/null")
        host.succeed("test $(systemctl show headplane -p User --value) = headplane")
        host.succeed("test $(stat -c %a /var/lib/headplane) = 700")
        host.succeed("test -s /var/lib/headplane/hp_persist.db")

    with subtest("API-key login and administrative access survive account separation"):
        machine.succeed("headscale apikeys create --expiration 1h > /tmp/fixture-api-key")
        machine.succeed("chmod 600 /tmp/fixture-api-key")
        machine.succeed("curl -fsS -c /tmp/cookies http://127.0.0.1:3000/admin/login > /dev/null")
        machine.succeed("curl -sS -b /tmp/cookies -c /tmp/cookies -D /tmp/login-headers --data-urlencode \"api_key=$(cat /tmp/fixture-api-key)\" http://127.0.0.1:3000/admin/login > /tmp/login-body")
        machine.succeed("grep -E '^HTTP/.* 302' /tmp/login-headers")
        machine.succeed("curl -fsS -b /tmp/cookies http://127.0.0.1:3000/admin/machines > /tmp/machines")
        machine.succeed("curl -fsS -b /tmp/cookies --data-urlencode action_id=create_user --data-urlencode username=fixture-user http://127.0.0.1:3000/admin/users > /tmp/create-user")
        machine.succeed("headscale users list --output json | jq -e '.[] | select(.name == \"fixture-user\")'")
        machine.succeed("curl -fsS -b /tmp/cookies http://127.0.0.1:3000/admin/users | grep -F fixture-user")

    with subtest("filesystem, secret, device and process boundaries"):
        machine.succeed("systemctl show headscale -p MainPID --value > /run/headplane-probe.pid; chmod 444 /run/headplane-probe.pid")
        machine.succeed("touch /tmp/host-private")
        machine.succeed("systemctl start headplane-probe.service")
        machine.succeed("test -e /var/lib/headplane/probe-state")
        machine.succeed("test ! -e /tmp/headplane-private")

    with subtest("generated cookie persists across restarts"):
        before = generated.succeed("sha256sum /var/lib/headplane/cookie-secret")
        generated.succeed("test $(wc -c < /var/lib/headplane/cookie-secret) = 32")
        generated.succeed("systemctl restart headplane")
        generated.wait_until_succeeds("curl -fsS http://127.0.0.1:3000/admin/login > /dev/null")
        assert generated.succeed("sha256sum /var/lib/headplane/cookie-secret") == before

    with subtest("missing managed cookie fails closed instead of generating a replacement"):
        machine.succeed("systemctl stop headplane; rm /run/headplane-fixture-cookie")
        machine.fail("systemctl start headplane")
        machine.succeed("test ! -e /run/headplane-fixture-cookie")
        machine.succeed("systemctl stop headplane")
  '';
}
