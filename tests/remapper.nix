{ inputs, pkgs, ... }:
let
  python = pkgs.python3.withPackages (p: [ p.evdev ]);
  request = pkgs.writeScriptBin "remapper-request" ''
    #!${python}/bin/python
    import json, socket, sys
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(8)
        client.connect("/run/remapper-fixture.sock")
        client.sendall(sys.argv[1].encode())
        response = json.loads(client.recv(4096))
        assert "error" not in response, response
        print(response["result"])
  '';
in
pkgs.testers.runNixOSTest {
  name = "apc-remapper";
  nodes.machine = { pkgs, ... }: {
    imports = [ "${inputs.self}/hosts/apc/remapper.nix" ];
    environment.systemPackages = [ python request ];
    # Give synthetic uinput devices the real receiver's observed identity.
    # The later production rule must assign the actual service permissions.
    services.udev.packages = [ (pkgs.writeTextDir "lib/udev/rules.d/60-remapper-fixture.rules" ''
      SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="fixture-remap-receiver", ENV{ID_VENDOR_ID}="046d", ENV{ID_MODEL_ID}="c547", ENV{ID_USB_INTERFACE_NUM}="02", ENV{ID_INPUT_MOUSE}="1", SYMLINK+="input/by-id/usb-Logitech_USB_Receiver-if02-event-mouse"
    '') ];
    systemd.services.remapper-fixture = {
      serviceConfig.ExecStart = "${python}/bin/python ${./remapper/fixture.py}";
    };
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    with subtest("missing receiver is retried without root"):
        machine.succeed("test $(systemctl show apc-mouse-remap -p User --value) = apc-mouse-remap")
        machine.succeed("systemctl start remapper-fixture")
        machine.wait_for_file("/dev/input/by-id/usb-Logitech_USB_Receiver-if02-event-mouse")
        machine.wait_until_succeeds("remapper-request probe", timeout=30)
        pid = machine.succeed("systemctl show apc-mouse-remap -p MainPID --value").strip()
        status = machine.succeed(f"cat /proc/{pid}/status")
        assert "CapEff:\t0000000000000000" in status, status
        assert "CapBnd:\t0000000000000000" in status, status
        assert "NoNewPrivs:\t1" in status, status
        machine.succeed(f"test $(stat -c %U /proc/{pid}) = apc-mouse-remap")
        keyboard = machine.succeed("remapper-request keyboard").strip()
        machine.fail(f"runuser -u apc-mouse-remap -- python -c 'import os; os.open(\"{keyboard}\", os.O_RDONLY | os.O_NONBLOCK)'")
    with subtest("unplug and a new input minor preserve mapping"):
        original = machine.succeed("readlink -f /dev/input/by-id/usb-Logitech_USB_Receiver-if02-event-mouse").strip()
        machine.succeed("remapper-request unplug")
        machine.wait_until_succeeds("test ! -e /dev/input/by-id/usb-Logitech_USB_Receiver-if02-event-mouse")
        replacement = machine.succeed("remapper-request replug").strip()
        assert replacement != original, (original, replacement)
        machine.wait_until_succeeds("remapper-request probe", timeout=30)
  '';
}
