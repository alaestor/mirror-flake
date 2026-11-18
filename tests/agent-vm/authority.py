"""Direct system-manager requests, not a simulation of polkit rule matching."""
import dbus

manager = dbus.Interface(dbus.SystemBus().get_object(
    "org.freedesktop.systemd1", "/org/freedesktop/systemd1"),
    "org.freedesktop.systemd1.Manager")
command = dbus.Array([dbus.Struct(("/run/current-system/sw/bin/touch",
    dbus.Array(["touch", "/run/agent-escaped"], signature="s"), False))], signature="(sasb)")
properties = dbus.Array([("ExecStart", command), ("User", "root"),
    ("NoNewPrivileges", False), ("Requires", dbus.Array(["sshd.service"], signature="s"))],
    signature="(sv)")


def denied(label, call):
    try:
        call()
    except dbus.DBusException as error:
        assert error.get_dbus_name() in {
            "org.freedesktop.DBus.Error.AccessDenied",
            "org.freedesktop.DBus.Error.InteractiveAuthorizationRequired",
            "org.freedesktop.systemd1.UnitExists",
            "org.freedesktop.systemd1.NotSupported",
        }, (label, str(error))
        print(label, error.get_dbus_name())
    else:
        raise AssertionError(label + " unexpectedly succeeded")


for name in ["agent-vm-session-bypass.service", "agent-vm-linger-bypass.service",
             "agent-vm-session-bypass.timer", "unrelated.service",
             "microvm@acceptance.service", "microvm-virtiofsd@acceptance.service"]:
    denied(name, lambda: manager.StartTransientUnit(name, "replace", properties,
        dbus.Array([], signature="(sa(sv))")))

# A grant for the installed fixed unit must not admit caller-defined auxiliary
# root units, even when the main requested unit is authorized by name.
denied("fixed unit with auxiliary service", lambda: manager.StartTransientUnit(
    "microvm@acceptance.service", "replace", properties,
    dbus.Array([("agent-vm-session-aux.service", properties)], signature="(sa(sv))")))
denied("change installed unit properties", lambda: manager.SetUnitProperties(
    "microvm@acceptance.service", True, dbus.Array([("CPUWeight", dbus.UInt64(900))], signature="(sv)")))
denied("unrelated installed unit", lambda: manager.StartUnit("sshd.service", "replace"))
denied("start shares directly", lambda: manager.StartUnit("microvm-virtiofsd@acceptance.service", "replace"))
