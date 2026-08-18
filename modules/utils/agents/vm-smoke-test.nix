/**
  # `nixosConfigurations.agent-vm-smoke-test`

  Phase 4's acceptance test target — "get *any* VM booting, with correct
  path identity. No harnesses yet." Not part of the host registry
  (`modules/host-plumbing/registry.nix`): it isn't a real fleet host, has no
  `hostIdentity`, and is meant to be built and thrown away, not deployed.

  **Running it.** `nix run .#...declaredRunner` on its own is not enough:
  it only executes the runner's `bin/microvm-run` (QEMU), while every
  `proto = "virtiofs"` share expects a `virtiofsd` already listening on a
  *relative* socket path. Without those you get
  `Failed to connect to 'agent-vm-smoke-test-virtiofs-ro-store.sock'`.
  The runner's `bin/virtiofsd-run` starts them, but it is a supervisord
  config with `user=root`, so unprivileged use means invoking each
  `virtiofsd` command from that config directly (they handle non-root fine,
  and drop the `--rlimit-nofile` bump). Do it all from one scratch
  directory, since the socket paths are relative to `$PWD`:

  ```
  R=$(rtk nix build --no-link --print-out-paths \
      .#nixosConfigurations.agent-vm-smoke-test.config.microvm.declaredRunner)
  mkdir -p /tmp/agent-vm && cd /tmp/agent-vm
  conf=$(grep -o '/nix/store/[^ ]*-supervisord.conf' "$(readlink -f "$R/bin/virtiofsd-run")")
  grep '^command=' "$conf" | grep virtiofsd | sed 's/^command=//' |
    while read -r c; do "$c" & done
  "$R/bin/microvm-run"          # or `sudo "$R/bin/virtiofsd-run" &` instead
  ssh -p 2222 user@localhost
  "$R/bin/microvm-shutdown"     # from the same directory, to stop it
  ```

  Don't launch it with `$PWD` inside the flake: `microvm-run` drops a QMP
  socket named after the VM next to itself, and a socket in the source tree
  makes the flake itself unevaluable ("has an unsupported type").

  The in-guest acceptance checks themselves live in
  `__reference/human-verify.md`.
*/
{ inputs, self, ... }:
{
  flake.nixosConfigurations.agent-vm-smoke-test = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      (self.lib.agents.mkAgentVm {
        name = "agent-vm-smoke-test";
        hostUser = "user";
        projectRoots = [
          "/home/user/Projects"
          "/mnt/Vault/.dotfiles/flake"
        ];
        authorizedKeys = [ self.data.vars.sshClientPublicKeys.apc ];
      })
    ];
  };
}
