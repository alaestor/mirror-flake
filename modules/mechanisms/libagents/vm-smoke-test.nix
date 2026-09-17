/**
  # `nixosConfigurations.agent-vm-smoke-test`

  An acceptance test target for a VM with correct path identity. It is not
  part of the host registry
  (`modules/host-plumbing/registry.nix`): it isn't a real fleet host, has no
  `hostIdentity`, and is meant to be built and thrown away, not deployed.

  **Running it:** `nix run .#agent-vm-run -- agent-vm-smoke-test`, then
  `ssh -p 2222 user@localhost`. Plain
  `nix run .#...config.microvm.declaredRunner` is *not* enough — it starts
  QEMU without the `virtiofsd` daemons every `proto = "virtiofs"` share
  needs, and dies with `Failed to connect to
  'agent-vm-smoke-test-virtiofs-ro-store.sock'`. See
  `modules/mechanisms/libagents/vm-run.nix` for what the wrapper does, why it wants
  `sudo`, and what `--unprivileged` costs you.

  The nix-daemon and gpg-agent channels live here rather than in a second
  guest. They need `agent-vm.enable = true` on the host (see
  `modules/mechanisms/libagents/vm-host.nix`); without it the guest boots
  normally and both proxies just fail to connect.

  The harness state directories are read-write shares. They come from the host
  and are not created by this configuration, so building
  it on a machine that lacks them is fine but *running* it there is not:
  virtiofsd refuses a source directory that does not exist. On a host with
  `agent-vm.enable`, systemd-tmpfiles has already made them.

  The in-guest acceptance checks themselves live in untracked working notes
  (not part of this repository).
*/
{ inputs, self, ... }:
let
  vmContributions = self.lib.agents.vmContributionsFor "/home/user" [
    "claude"
    "codex"
    "deepseek"
    "headroom"
    "serena"
  ];
in
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

        # The same state directories the declared VM gets on `apc`,
        # so the shared-config acceptance checks can be run against the
        # throwaway guest instead of the deployed one. Named through
        # `flake.lib.agents` — the smoke test is a caller, and callers are
        # allowed to know what a harness keeps where; the VM layer is not.
          inherit (vmContributions) stateDirs localStateDirs guestEnvironment;

        # Both channels, so the smoke test stays the one guest
        # everything is verified against. The host end of these lives on the
        # host configuration (`flake.modules.nixos.agent-vm`), so this VM's
        # channels only work on a host that has that module enabled.
        channels = {
          nixDaemon.enable = true;
          gpgAgent = {
            enable = true;
            certificates = [ self.data.vars.identities.administrative.pgp.certificate ];
            ultimatelyTrusted = [ self.data.vars.identities.administrative.pgp.fingerprint ];
          };
        };
      })
    ];
  };
}
