{ inputs, pkgs, ... }:
pkgs.testers.runNixOSTest {
  name = "ipv4-only-runtime";
  # global-config owns nixpkgs defaults, so the fixture needs mutable pkgs.
  node.pkgsReadOnly = false;
  nodes = {
    machine = { pkgs, ... }: {
      imports = [
        inputs.self.modules.nixos.global-config
        inputs.self.modules.nixos.telemetry
      ];
      networking.networkmanager.enable = true;
      services.rpcbind.enable = true;
      services.tailscale.enable = true;
      telemetry = {
        enable = true;
        interface = "eth1";
        pushUrl = "http://127.0.0.1:1/loki/api/v1/push";
      };
      environment.systemPackages = [ pkgs.python3 ];
    };
    peer = { pkgs, ... }: {
      imports = [ inputs.self.modules.nixos.global-config ];
      environment.systemPackages = [ pkgs.curl ];
    };
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("NetworkManager.service")
    machine.wait_for_unit("rpcbind.service")
    machine.wait_for_unit("tailscaled.service")
    machine.wait_for_unit("telemetry-metrics.socket")
    peer.wait_for_unit("multi-user.target")

    with subtest("the boot policy disables IPv6 operations, not just addresses"):
        machine.succeed("grep -qw ipv6.disable=1 /proc/cmdline")
        machine.succeed("test $(cat /sys/module/ipv6/parameters/disable) = 1")
        machine.succeed("test -z \"$(ip -6 address show)\"")
        machine.succeed("python -c 'import socket; s = socket.socket(socket.AF_INET); s.bind((\"127.0.0.1\", 0))'")
        machine.succeed("""python - <<'PY'
    import errno
    import socket
    try:
        socket.socket(socket.AF_INET6)
    except OSError as error:
        assert error.errno == errno.EAFNOSUPPORT, error
    else:
        raise AssertionError("IPv6 socket creation must fail")
    PY""")

    with subtest("device-bound telemetry still works over IPv4"):
        peer.wait_until_succeeds("curl --fail --silent --show-error --max-time 5 http://machine:9100/metrics -o /tmp/metrics && grep -q '^node_uname_info' /tmp/metrics")
  '';
}
