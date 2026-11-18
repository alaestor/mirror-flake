import shlex
import time

machine.start()
machine.wait_for_unit("multi-user.target")
machine.succeed("systemctl start user@1000.service")
machine.wait_for_unit("user@1000.service")


def user(command, account="fixture", uid=1000):
    return (f"runuser -u {account} -- env XDG_RUNTIME_DIR=/run/user/{uid} "
            f"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus "
            f"SSH_AUTH_SOCK=/run/user/{uid}/fixture-ssh-agent "
            "bash -lc " + shlex.quote(command) + " </dev/null")


def run(command):
    return machine.succeed(user(command))


def remote(command):
    return run("timeout 120s agent-vm-session -- bash -elc " + shlex.quote(command))


def background(name, command):
    run(f"nohup timeout 150s agent-vm-session -- bash -elc {shlex.quote(command)} "
        f">/home/fixture/{name}.out 2>/home/fixture/{name}.err </dev/null &")


def down(check_scopes=True):
    machine.wait_until_succeeds("systemctl show microvm@acceptance.service -p ActiveState --value | grep -Ex 'inactive|failed'", timeout=45)
    machine.wait_until_succeeds("systemctl show microvm-virtiofsd@acceptance.service -p ActiveState --value | grep -Ex 'inactive|failed'", timeout=30)
    machine.wait_until_succeeds("! ss -ltn | grep -q ':2222 '", timeout=15)
    if check_scopes:
        machine.wait_until_succeeds(user("test -z \"$(systemctl --user list-units 'agent-vm-session-*.scope' --state=active,activating --no-legend --plain)\""), timeout=15)
    # Daemons and sockets must not survive shutdown, even after failed boot.
    machine.succeed("! pgrep -x virtiofsd && ! pgrep -f '^microvm@acceptance '")
    machine.succeed("! ss -xlpn | grep -E 'acceptance(-virtiofs-.*)?[.]sock'")


with subtest("real system-manager authorization denies transient root definitions"):
    run("timeout 30s agent-vm-authority-test")
    machine.succeed("test ! -e /run/agent-escaped")
    machine.fail(user("systemctl --no-ask-password start microvm@acceptance.service", "other", 1001))
    machine.fail(user("systemctl --no-ask-password restart microvm@acceptance.service"))
    machine.fail(user("touch /var/lib/microvms/group-write-forbidden"))
    machine.fail(user("touch /var/lib/microvms/acceptance/group-write-forbidden"))

with subtest("a scope protects slow startup and sessions longer than idle linger"):
    run("install -dm0700 /home/fixture/.ssh; cp "
        "/etc/agent-vm-fixture-id /home/fixture/.ssh/id_ed25519; "
        "chmod 600 /home/fixture/.ssh/id_ed25519")
    background("long", "touch /home/fixture/Projects/started; sleep 16; echo long-done")
    machine.wait_until_succeeds(user("systemctl --user list-units 'agent-vm-session-*.scope' --state=active --no-legend | grep ."), timeout=15)
    time.sleep(6)
    machine.succeed("systemctl is-active microvm@acceptance.service")
    machine.wait_for_file("/home/fixture/Projects/started", timeout=200)
    machine.succeed("systemctl is-active microvm@acceptance.service")
    first_pid = machine.succeed("systemctl show microvm@acceptance -p MainPID --value").strip()
    assert "second-session" in remote("echo second-session")
    assert machine.succeed("systemctl show microvm@acceptance -p MainPID --value").strip() == first_pid
    run("agent-vm-stop")
    time.sleep(5)
    machine.succeed("systemctl is-active microvm@acceptance.service")
    machine.wait_until_succeeds("grep -q long-done /home/fixture/long.out", timeout=30)
    down()

with subtest("actual virtiofs identity, writable state, hidden paths and read-only store"):
    machine.succeed("grep -x host-only /home/fixture/hidden/sentinel")
    assert "1000" in remote("id -u")
    remote("test -r /home/fixture/Projects/started; "
           "test ! -e /home/fixture/hidden/sentinel; "
           "test $(findmnt -n -o FSTYPE /home/fixture/Projects) = virtiofs; "
           "echo shared-bytes > /home/fixture/shared-state/persist; "
           "echo block-bytes > /home/fixture/local-state/persist; "
           "stat -c %u /home/fixture/shared-state/persist | grep -x 1000")
    machine.succeed("test $(stat -c %u /home/fixture/shared-state/persist) = 1000; grep -x shared-bytes /home/fixture/shared-state/persist")
    # Guest root is used only to distinguish a real read-only mount from DAC.
    # Its daemon is disabled, so there is no writable local-store fallback.
    remote("findmnt -n -o OPTIONS /nix/store | grep -w ro; "
           "test -e /run/root-write-positive; test -e /run/store-readonly-passed; "
           "! systemctl is-active --quiet nix-daemon.service")

with subtest("Nix channel uses a real untrusted host peer and fails without its listener"):
    assert "daemon" in remote("printf '%s' \"$NIX_REMOTE\"")
    remote("echo daemon-add > /home/fixture/Projects/add; nix-store --add /home/fixture/Projects/add > /home/fixture/shared-state/added")
    added = machine.succeed("cat /home/fixture/shared-state/added").strip()
    machine.succeed("nix-store --check-validity " + shlex.quote(added))
    # Exercise the daemon's actual peer-trust decision, not only unit settings.
    remote("nix --option trusted-users fixture --store daemon store ping 2>/home/fixture/shared-state/trust.err")
    machine.succeed("grep -E 'not a trusted user|restricted setting' /home/fixture/shared-state/trust.err")
    machine.succeed("systemctl stop agent-vm-nix-daemon.socket 'agent-vm-nix-daemon@*.service'")
    remote("if timeout 8s nix --store daemon store ping; then exit 1; fi")
    machine.succeed("systemctl start agent-vm-nix-daemon.socket")

with subtest("restricted GPG channel signs and decrypts but cannot export a secret"):
    machine.succeed("systemctl start fixture-gpg")
    machine.wait_for_file("/run/user/1000/gnupg/S.gpg-agent.extra", timeout=30)
    remote("echo signed > /home/fixture/Projects/message; "
           "gpg --batch --yes --detach-sign /home/fixture/Projects/message; "
           "gpg --batch --verify /home/fixture/Projects/message.sig /home/fixture/Projects/message; "
           "gpg --batch --yes --trust-model always --recipient fixture@example.test --encrypt /home/fixture/Projects/message; "
           "gpg --batch --decrypt /home/fixture/Projects/message.gpg | grep -x signed; "
           "! gpg --batch --export-secret-keys > /home/fixture/shared-state/exported; "
           "test ! -s /home/fixture/shared-state/exported")
    machine.succeed("systemctl stop agent-vm-gpg-agent.socket 'agent-vm-gpg-agent@*.service'")
    remote("if timeout 8s gpg --batch --yes --detach-sign /home/fixture/Projects/message; then exit 1; fi")
    machine.succeed("systemctl start agent-vm-gpg-agent.socket")

with subtest("SSH forwarding grants signing authority without sharing the private key"):
    machine.succeed("systemctl start fixture-ssh-agent")
    machine.wait_for_file("/run/user/1000/fixture-ssh-agent", timeout=15)
    run("ssh-add /home/fixture/.ssh/id_ed25519; "
        "ssh-keygen -y -f /home/fixture/.ssh/id_ed25519 > /home/fixture/Projects/forwarded.pub")
    remote("test ! -e /home/fixture/.ssh/id_ed25519; "
           "ssh-add -T /home/fixture/Projects/forwarded.pub")
    machine.succeed("systemctl stop fixture-ssh-agent")
    remote("if ssh-add -T /home/fixture/Projects/forwarded.pub; then exit 1; fi")

with subtest("recovery stops active guest and shares; local block state survives reboot"):
    background("interrupted", "echo ready; sleep 100")
    machine.wait_until_succeeds("grep -q ready /home/fixture/interrupted.out", timeout=120)
    run("agent-vm-restart")
    down()
    remote("grep -x shared-bytes /home/fixture/shared-state/persist; grep -x block-bytes /home/fixture/local-state/persist")
    down()

with subtest("failed startup returns an error without a native fallback and cleans up"):
    machine.succeed("touch /run/fixture-fail-start")
    machine.fail(user("timeout 100s agent-vm-session -- touch /home/fixture/Projects/should-not-run"))
    machine.succeed("test ! -e /home/fixture/Projects/should-not-run")
    down()
    machine.succeed("rm /run/fixture-fail-start; systemctl reset-failed microvm@acceptance.service")
    assert "fresh" in remote("echo fresh")
    down()

with subtest("a killed scope and a restarted controller leave no permanent references"):
    background("killed", "echo kill-ready; sleep 100")
    machine.wait_until_succeeds("grep -q kill-ready /home/fixture/killed.out", timeout=120)
    run("systemctl --user kill --signal=KILL agent-vm-lifecycle.service")
    machine.wait_until_succeeds(user("systemctl --user is-active agent-vm-lifecycle.service"))
    run("systemctl --user kill --signal=KILL 'agent-vm-session-*.scope'")
    down()

with subtest("user-manager exit tears down active guest and shares"):
    background("logout", "echo logout-ready; sleep 100")
    machine.wait_until_succeeds("grep -q logout-ready /home/fixture/logout.out", timeout=120)
    machine.succeed("systemctl stop user@1000.service")
    down(check_scopes=False)
