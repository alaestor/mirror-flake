## nixcage

# nixcage

Vendored from [nixcage](https://github.com/hamidr/nixcage) (GPL-3.0).
Exports the disabled-by-default NixOS `nixcage` feature and the `nixcage`
package/app.

`nixcage` gives an AI coding agent a NixOS microVM instead of a namespace
sandbox: `nixcage init` writes a per-project `.nixcage-vm/` flake wiring
[microvm.nix](https://github.com/astro/microvm.nix), a base VM module and
the project's own `nixcage.vm.nix`; `nixcage build` / `start` / `shell`
then build and enter it. The project directory is shared into the guest at
`/workspace` and API keys are piped in through tmpfs, never written to disk.

This is a heavier isolation boundary than `claude-sandbox` — a real kernel
and a real network namespace rather than bubblewrap — at the cost of a VM
build and KVM. Reach for it when an agent needs to run untrusted code, not
merely to be kept out of the rest of the filesystem.

Upstream's CLI and base VM module live in `data/utils/nixcage/` alongside the
`package.nix` derived from the upstream flake. They carry a license tag and
changes marked `LOCAL DEVIATION`:

- the generated per-project flake no longer takes `github:hamidr/nixcage`
as an input; the base VM module is imported by store path from
`NIXCAGE_BASE_MODULE`, which the wrapper pins to the vendored copy. The
generated VM still fetches `nixpkgs` and `microvm.nix` itself, since it is
an independent flake built out of a staging directory.

The guest still needs `/dev/kvm`, so `nixcage.kvmUsers` adds the accounts
that may run VMs to the `kvm` group.
