#!/usr/bin/env bash
# All bookkeeping is user-owned. The only system-manager mutations name fixed,
# installed services; no caller-supplied root unit definitions are accepted.
set -euo pipefail

operation=${1:?missing lifecycle operation}
shift
vm_unit="microvm@${AGENT_VM_NAME}.service"
shares_unit="microvm-virtiofsd@${AGENT_VM_NAME}.service"
scope_prefix="agent-vm-session-${AGENT_VM_NAME}-"
state="${XDG_RUNTIME_DIR:?a running user manager is required}/agent-vm-${AGENT_VM_NAME}"
umask 077
mkdir -p "$state"
exec 9>"$state/lock"

lock() { flock --timeout 30 9; }
unlock() { flock --unlock 9; }
active_scopes() {
    # A failed query must fail the controller, never mean "no sessions".
    systemctl --user list-units "${scope_prefix}*.scope" \
        --state=active,activating --no-legend --plain
}
system_control() {
    timeout 25s systemctl --no-ask-password "$@"
}

case "$operation" in
    session)
        # Register the reference before any startup/readiness work, so slow
        # boots and a linger interval shorter than startup cannot lose it.
        exec 9>&-
        exec systemd-run --user --scope --collect --quiet \
            --unit="${scope_prefix}$$-${RANDOM}" \
            -- "$AGENT_VM_INNER" "$@"
        ;;
    acquire)
        forwards=()
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --forward|--reverse-forward)
                    [[ $# -ge 2 ]] || { echo "agent-vm-session: $1 needs a forwarding specification" >&2; exit 2; }
                    if [[ "$1" == --forward ]]; then forwards+=(-L "$2"); else forwards+=(-R "$2"); fi
                    shift 2
                    ;;
                *) break ;;
            esac
        done
        if [[ ${1:-} == -- ]]; then shift; fi
        [[ $# -gt 0 ]] || { echo "usage: agent-vm-session [--forward|--reverse-forward SPEC]... -- COMMAND..." >&2; exit 2; }
        systemctl --user start agent-vm-lifecycle.service
        lock
        rm -f "$state/stop-requested"
        system_control start --no-block "$vm_unit"
        unlock
        exec 9>&-
        ready=0
        deadline=$((SECONDS + AGENT_VM_READY_TIMEOUT))
        while ((SECONDS < deadline)); do
            # QEMU accepts TCP before guest sshd exists. A bare TCP probe
            # can release startup early and let idle shutdown kill the boot.
            if ssh-keyscan -T 1 -p "$AGENT_VM_PORT" -t ed25519 127.0.0.1 >/dev/null 2>&1; then
                ready=1
                break
            fi
            if systemctl is-failed --quiet "$vm_unit"; then
                echo "agent-vm-session: ${AGENT_VM_NAME} failed to start; inspect its system journal" >&2
                exit 1
            fi
            sleep 1
        done
        [[ "$ready" == 1 ]] || {
            echo "agent-vm-session: ${AGENT_VM_NAME} did not become reachable within ${AGENT_VM_READY_TIMEOUT}s" >&2
            exit 1
        }
        # SSH joins argv into a shell command. Quote each original argument,
        # including empty strings and newlines, for the guest's Bash shell.
        remote_command=""
        for argument in "$@"; do
            printf -v quoted '%q' "$argument"
            remote_command+="$quoted "
        done
        exec ssh -tA -p "$AGENT_VM_PORT" \
            -o "UserKnownHostsFile=$AGENT_VM_KNOWN_HOSTS" \
            -o StrictHostKeyChecking=yes -o ExitOnForwardFailure=yes \
            "${forwards[@]}" "${AGENT_VM_USER}@localhost" -- "$remote_command"
        ;;
    monitor)
        idle_since=0
        while true; do
            lock
            scopes=$(active_scopes)
            now=$SECONDS
            if [[ -n "$scopes" ]]; then
                idle_since=0
            else
                if [[ "$idle_since" == 0 ]]; then idle_since=$now; fi
                if [[ -e "$state/stop-requested" ]] || ((now - idle_since >= AGENT_VM_LINGER)); then
                    # Shared lock serializes this decision with acquisition
                    # and recovery. A newly registered scope queues startup
                    # after this stop completes, rather than racing it.
                    system_control stop "$vm_unit"
                    rm -f "$state/stop-requested"
                    idle_since=$now
                fi
            fi
            unlock
            sleep 1
        done
        ;;
    stop)
        systemctl --user start agent-vm-lifecycle.service
        lock
        scopes=$(active_scopes)
        if [[ -n "$scopes" ]]; then
            touch "$state/stop-requested"
            echo "agent-vm-stop: active sessions retained; stopping after the last exits." >&2
        else
            system_control stop "$vm_unit"
            rm -f "$state/stop-requested"
        fi
        ;;
    restart)
        lock
        # Explicit recovery interrupts active sessions. Stop the shares and
        # leave everything down; the next acquisition starts fresh daemons.
        system_control stop "$vm_unit"
        system_control stop "$shares_unit"
        rm -f "$state/stop-requested"
        echo "agent-vm-restart: stopped guest and shares; the next session starts fresh." >&2
        ;;
    *) echo "unknown lifecycle operation: $operation" >&2; exit 2 ;;
esac
