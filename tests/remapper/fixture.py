"""Disposable input source/control socket; never opens host hardware."""

import json
import select
import socket
import time

from evdev import InputDevice, UInput, ecodes as e, list_devices


def mouse():
    return UInput(
        {e.EV_KEY: [e.BTN_LEFT, e.BTN_FORWARD, e.BTN_BACK, e.BTN_TASK],
         e.EV_REL: [e.REL_X, e.REL_Y]},
        name="fixture-remap-receiver",
    )


receiver = mouse()
keyboard = UInput({e.EV_KEY: [e.KEY_A]}, name="fixture-unrelated-keyboard")
placeholder = None
server = socket.socket(socket.AF_UNIX)
server.bind("/run/remapper-fixture.sock")
server.listen()
while True:
    connection, _ = server.accept()
    with connection:
        command = connection.recv(100).decode().strip()
        try:
            if command == "unplug":
                receiver.close()
                placeholder = UInput({e.EV_KEY: [e.KEY_B]}, name="fixture-minor-holder")
                result = "unplugged"
            elif command == "replug":
                receiver = mouse()
                result = receiver.device.path
            elif command == "keyboard":
                result = keyboard.device.path
            elif command == "probe":
                outputs = [InputDevice(path) for path in list_devices()]
                output = next(device for device in outputs
                              if device.name == "APC G502 X numpad keys")
                for source in [e.BTN_FORWARD, e.BTN_BACK, e.BTN_TASK]:
                    receiver.write(e.EV_KEY, source, 1)
                    receiver.write(e.EV_KEY, source, 0)
                    receiver.syn()
                observed = set()
                deadline = time.monotonic() + 5
                expected = {e.KEY_KPPLUS, e.KEY_KPMINUS, e.KEY_KPASTERISK}
                while observed != expected and time.monotonic() < deadline:
                    if select.select([output.fd], [], [], 0.1)[0]:
                        observed.update(event.code for event in output.read()
                                        if event.type == e.EV_KEY and event.value == 1)
                for device in outputs:
                    device.close()
                assert observed == expected, observed
                result = "mapped"
            else:
                raise ValueError(command)
            connection.sendall(json.dumps({"result": result}).encode())
        except Exception as error:
            connection.sendall(json.dumps({"error": repr(error)}).encode())
