{ inputs, pkgs, ... }:
let
  # Replace only key admission. Never decrypt or use the personal signing key.
  cacheModule = (import "${inputs.self}/modules/serve/services/nix-cache.nix" {
    inherit inputs;
    self = inputs.self // {
      secrets = inputs.self.secrets // {
        nixStoreSigning = _: { exists = true; subpath = "disposable-key"; };
      };
    };
  }).flake.modules.nixos.serve-nix-cache;
  payload = pkgs.writeText "cache-disposable-payload" "signed fixture bytes\n";
  probe = pkgs.writeShellScript "cache-sandbox-probe" ''
    set -eu
    test -r ${payload}
    test ! -r /home/fixture/sentinel
    test ! -r /mnt/fixture/sentinel
    test ! -r /media/fixture/sentinel
    test ! -e /dev/input
    test -e /dev/null
    test "$(id -u)" != 0
    grep -Eq '^CapEff:[[:space:]]+0000000000000000$' /proc/self/status
    grep -Eq '^CapBnd:[[:space:]]+0000000000000000$' /proc/self/status
    grep -Eq '^NoNewPrivs:[[:space:]]+1$' /proc/self/status
    if touch /run/cache-forbidden 2>/dev/null; then exit 1; fi
    if touch /etc/cache-forbidden 2>/dev/null; then exit 1; fi
    touch /tmp/cache-private-positive
  '';
in
pkgs.testers.runNixOSTest {
  name = "nix-cache";
  nodes = {
    server = { lib, pkgs, ... }: {
      imports = [ cacheModule ];
      options.hostIdentity = lib.mkOption { type = lib.types.attrs; };
      config = {
        hostIdentity = { name = "fixture"; primaryUser = "fixture"; };
        users.users.fixture.isNormalUser = true;
        nix-store-signing.enable = lib.mkForce false;
        serve.nix-cache = { enable = true; authority = "cache.example.test"; privateInterface = "eth1"; };
        services.nix-serve.secretKeyFile = lib.mkForce "/run/cache-secret";
        systemd.services.nix-serve.wantedBy = lib.mkForce [ ];
        systemd.services.nix-serve.serviceConfig.ExecStartPost = probe;
        system.extraDependencies = [ payload ];
        environment.systemPackages = [ pkgs.curl ];
        systemd.tmpfiles.rules = [
          "d /home/fixture 0755 root root -"
          "f /home/fixture/sentinel 0644 root root - forbidden"
          "d /mnt/fixture 0755 root root -"
          "f /mnt/fixture/sentinel 0644 root root - forbidden"
          "d /media/fixture 0755 root root -"
          "f /media/fixture/sentinel 0644 root root - forbidden"
        ];
      };
    };
    client = { pkgs, ... }: {
      environment.systemPackages = [ pkgs.curl ];
      nix.settings.experimental-features = [ "nix-command" ];
      nix.settings.substituters = pkgs.lib.mkForce [ ];
    };
  };
  testScript = ''
    start_all()
    server.wait_for_unit("multi-user.target")
    client.wait_for_unit("multi-user.target")
    server.succeed("nix-store --generate-binary-cache-key cache.example.test /run/cache-secret /tmp/cache-public; chmod 600 /run/cache-secret")
    server.succeed("systemctl start nix-serve")
    server.wait_for_unit("nix-serve.service")
    client.wait_until_succeeds("curl --fail --max-time 5 http://server:5000/nix-cache-info")
    with subtest("the production sandbox passes allowed and denied access probes"):
        server.succeed("test ! -e /tmp/cache-private-positive")
        server.succeed("test ! -e /run/cache-forbidden")
    with subtest("real substitutions require the disposable trusted signature"):
        client.fail("nix path-info ${payload}")
        client.fail("nix copy --from http://server:5000 --option trusted-public-keys \"\" ${payload}")
        public_key = server.succeed("cat /tmp/cache-public").strip()
        client.succeed(f"nix copy --from http://server:5000 --option trusted-public-keys '{public_key}' ${payload}")
        client.succeed("nix store verify --sigs-needed 1 --option trusted-public-keys '" + public_key + "' ${payload}")
        assert client.succeed("cat ${payload}") == "signed fixture bytes\n"
  '';
}
