/**
  # `agent-vm-run`

  One command for "boot an agent VM on this machine and get a shell", so
  manual verification (`__reference/human-verify.md`) doesn't start with a
  five-line shell incantation.

  `nix run .#nixosConfigurations.<vm>.config.microvm.declaredRunner` is not
  enough on its own: it executes only the runner's `bin/microvm-run` (QEMU),
  while each `proto = "virtiofs"` share needs a `virtiofsd` already listening
  on a socket path that is **relative to the current directory**. Miss that
  and QEMU exits immediately with `Failed to connect to
  '<vm>-virtiofs-<tag>.sock'`. This wrapper builds the runner, starts the
  daemons in a scratch state directory, waits for their sockets, then runs
  QEMU in the foreground and tears the daemons down on exit.

  ```
  nix run .#agent-vm-run -- agent-vm-smoke-test
  ssh -p 2222 user@localhost
  ```

  **Privileged by default, and that matters.** The runner's
  `bin/virtiofsd-run` is a supervisord config with `user=root`, so this runs
  it under `sudo` unless it is already root. `--unprivileged` skips sudo and
  invokes each `virtiofsd` from that config directly, which boots fine and
  preserves path identity, but **squashes ownership**: an unprivileged
  virtiofsd cannot present files owned by other users, so everything on the
  `/nix/store` share appears as `nobody:nogroup` (65534) inside the guest.
  That is not cosmetic — `logrotate` refuses a config file it does not see as
  root-owned, so `logrotate-checkconf.service` fails on boot and anything
  else that checks ownership of store paths may follow. Files owned by the
  invoking user (project roots) still map correctly, which is why path
  identity checks pass either way. Use `--unprivileged` for a quick boot
  test, not to judge whether the guest is healthy.

  This deliberately does not install a systemd unit or a persistent state
  directory; VM lifecycle management is Phase 6's job in
  `__reference/implementation-guide-agent-microvms.md`, and guessing ahead of
  it here would be the "drive-by" kind of change. Everything below is scoped
  to running one VM interactively, from a directory outside the flake (a QMP
  socket dropped into the source tree makes the flake itself unevaluable).
*/
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      name = "agent-vm-run";
      package = pkgs.writeShellApplication {
        inherit name;
        runtimeInputs = [
          pkgs.nix
          pkgs.gnugrep
          pkgs.gnused
          pkgs.coreutils
        ];
        text = ''
          usage="usage: ${name} <vm-name> [--state DIR] [--unprivileged] [--flake REF]"
          vm=""
          state=""
          flake="."
          privileged=1

          while [ $# -gt 0 ]; do
            case "$1" in
              --state) state=''${2:?$usage}; shift 2 ;;
              --flake) flake=''${2:?$usage}; shift 2 ;;
              --unprivileged) privileged=0; shift ;;
              -h|--help) echo "$usage"; exit 0 ;;
              -*) echo "$usage" >&2; exit 2 ;;
              *) vm=$1; shift ;;
            esac
          done
          [ -n "$vm" ] || { echo "$usage" >&2; exit 2; }
          state=''${state:-''${XDG_RUNTIME_DIR:-/tmp}/agent-vm/$vm}

          runner=$(nix build --no-link --print-out-paths \
            "$flake#nixosConfigurations.$vm.config.microvm.declaredRunner")

          # Socket paths in the generated QEMU command line are relative, so
          # the daemons and QEMU must agree on one working directory. Stale
          # sockets from a previous run make QEMU fail with "Connection
          # refused" rather than "No such file", so clear them first.
          mkdir -p "$state"
          cd "$state"
          rm -f ./*.sock

          conf=$(grep -o '/nix/store/[^ ]*-supervisord\.conf' \
            "$(readlink -f "$runner/bin/virtiofsd-run")")
          mapfile -t daemons < <(
            grep '^command=/nix/store/.*virtiofsd' "$conf" | sed 's/^command=//'
          )

          pids=()
          cleanup() {
            for pid in ''${pids[@]+"''${pids[@]}"}; do
              kill "$pid" 2>/dev/null || true
            done
          }
          trap cleanup EXIT

          if [ "$privileged" = 1 ] && [ "$(id -u)" != 0 ]; then
            sudo "$runner/bin/virtiofsd-run" &
            pids+=($!)
          elif [ "$privileged" = 1 ]; then
            "$runner/bin/virtiofsd-run" &
            pids+=($!)
          else
            echo "${name}: unprivileged virtiofsd; store paths will appear" \
                 "owned by nobody inside the guest" >&2
            for daemon in "''${daemons[@]}"; do
              "$daemon" >> "virtiofsd-$(basename "$daemon").log" 2>&1 &
              pids+=($!)
            done
          fi

          for _ in $(seq 100); do
            count=$(find . -maxdepth 1 -name '*-virtiofs-*.sock' | wc -l)
            [ "$count" -ge "''${#daemons[@]}" ] && break
            sleep 0.2
          done

          echo "${name}: state directory $state" >&2
          echo "${name}: stop with '$runner/bin/microvm-shutdown' from there" >&2
          "$runner/bin/microvm-run"
        '';
      };
    in
    {
      packages.${name} = package;
      apps.${name} = {
        meta.description = "Boot a microvm.nix agent VM, starting its virtiofs daemons first";
        program = lib.getExe package;
      };
    };
}
