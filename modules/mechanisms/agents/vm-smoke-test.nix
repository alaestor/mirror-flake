/**
  # `nixosConfigurations.agent-vm-smoke-test`

  Phase 4's acceptance test target — "get *any* VM booting, with correct
  path identity. No harnesses yet." Not part of the host registry
  (`modules/host-plumbing/registry.nix`): it isn't a real fleet host, has no
  `hostIdentity`, and is meant to be built and thrown away, not deployed.

  **Running it:** `nix run .#agent-vm-run -- agent-vm-smoke-test`, then
  `ssh -p 2222 user@localhost`. Plain
  `nix run .#...config.microvm.declaredRunner` is *not* enough — it starts
  QEMU without the `virtiofsd` daemons every `proto = "virtiofs"` share
  needs, and dies with `Failed to connect to
  'agent-vm-smoke-test-virtiofs-ro-store.sock'`. See
  `modules/mechanisms/agents/vm-run.nix` for what the wrapper does, why it wants
  `sudo`, and what `--unprivileged` costs you.

  Phase 5 added the nix-daemon and gpg-agent channels here rather than in a
  second guest. They need `agent-vm.enable = true` on the host (see
  `modules/mechanisms/agents/vm-host.nix`); without it the guest boots
  normally and both proxies just fail to connect.

  The in-guest acceptance checks themselves live in
  `__reference/microvm/human-verify.md`.
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

        # Phase 5: both channels, so the smoke test stays the one guest
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
