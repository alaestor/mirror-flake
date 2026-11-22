{ fleet, ... }:
let
  tailnet = fleet.tailnets."0x04cc";
  apcSshPort = toString fleet.ports.apc.ssh;
  deepseekPort = toString fleet.ports.shared.deepseek-web;
in
{
  nixOnDroid = [
    (import ./system.nix {
      inherit tailnet;
      ports = fleet.ports.noblesse;
      builderSshPort = fleet.ports.apc.ssh;
    })
  ];
  homeManager = [
    ({ lib, pkgs, ... }: {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "ds-tunnel";
          runtimeInputs = [ pkgs.openssh ];
          text = ''
            if [[ $# != 1 ]]; then
              echo 'Usage: ds-tunnel {start|stop|status}' >&2
              exit 2
            fi

            target=${lib.escapeShellArg "user@apc.${tailnet.dnsSuffix}"}
            socket="$HOME/.ssh/ds-tunnel.sock"
            ssh_args=(-S "$socket" -p ${apcSshPort})

            case "$1" in
              start)
                if ! ssh "''${ssh_args[@]}" -O check "$target" >/dev/null 2>&1; then
                  ssh "''${ssh_args[@]}" -MfNT -a -x \
                    -o ControlPersist=no -o ExitOnForwardFailure=yes \
                    -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
                    -o StrictHostKeyChecking=yes \
                    -L 127.0.0.1:${deepseekPort}:127.0.0.1:${deepseekPort} "$target"
                fi
                echo 'Tunnel open. Use the full ds-native launch URL on this phone.'
                ;;
              stop)   exec ssh "''${ssh_args[@]}" -O exit "$target" ;;
              status) exec ssh "''${ssh_args[@]}" -O check "$target" ;;
              *)
                echo 'Usage: ds-tunnel {start|stop|status}' >&2
                exit 2
                ;;
            esac
          '';
        })
      ];
    })
  ];
}
