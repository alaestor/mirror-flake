/**
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
*/
{ self, ... }:
let
  packageFile = self.data.path "utils/nixcage/package.nix";

  mkNixcage = pkgs: pkgs.callPackage packageFile { };
in
{
  flake.lib.mkNixcage = mkNixcage;

  flake.modules.nixos.nixcage =
    { config, lib, pkgs, ... }:
    let
      cfg = config.nixcage;
    in
    {
      options.nixcage = {
        enable = lib.mkEnableOption "the nixcage microVM environment for coding agents";

        package = lib.mkOption {
          type = lib.types.package;
          default = mkNixcage pkgs;
          defaultText = lib.literalExpression "the vendored nixcage package";
          description = "The nixcage CLI to install.";
        };

        kvmUsers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "alaestor" ];
          description = ''
            Accounts joined to the `kvm` group. Without it `nixcage start`
            cannot open `/dev/kvm` and the VM falls back to unusably slow
            emulation, if it starts at all.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [
          cfg.package
          pkgs.openssh
        ];

        users.groups.kvm.members = cfg.kvmUsers;

        # The generated VM flake is built out of a staging directory, so the
        # host needs flakes and the new CLI available to unprivileged callers.
        nix.settings.experimental-features = [
          "nix-command"
          "flakes"
        ];
      };
    };

  perSystem =
    { lib, pkgs, ... }:
    let
      nixcage = mkNixcage pkgs;
    in
    {
      packages.nixcage = nixcage;
      apps.nixcage = {
        meta.description = "Manage NixOS microVM environments for coding agents";
        program = lib.getExe nixcage;
      };
    };
}
