{ config, inputs, ...} :
let
  constants = import (inputs.self.data.path "cryptid/constants.nix");

in
with constants;
{
  # Something between here and 8c50a710ddca43d7a530fb805ad55bde8d0141c5 breaks mounting the btrfs partition... Too lazy to bisect.
  # TODO(workaround): occassionally check if cryptid nixpkgs is fixed
  nucleus.inputs.cryptid-nixpkgs.url = "nixpkgs/4c1018dae018162ec878d42fec712642d214fdfa";

  /**
    Bootable installer ISO (~1.5GB) intended for offline management of cryptographic identities; not intended for system installation. Provides various commandline tools for working with pgp, yubikeys, and veracrypt containers.
  */
  host.cryptid = {
    description = "Offline cryptographic identity management ISO.";
    primaryUser = "user";
    stateVersion = "26.05";
    nixpkgs = inputs.cryptid-nixpkgs;

    # TODO(hosts): abstract path indirection
    modules = [
      { _module.args.cryptidConstants = constants; }
      ../../hosts/cryptid/storage.nix
      ../../hosts/cryptid/system.nix
      ({config, pkgs, lib, ...} :
  let
    username = config.hostIdentity.primaryUser;
    scriptContext = constants // import (inputs.self.data.path "cryptid/script-context.nix") {
      inherit constants username;
    };
    scriptCatalog = import (inputs.self.data.path "cryptid") {
      inherit lib pkgs;
      context = scriptContext;
    };

  in {

    # platform
    imports = with inputs.self.modules.nixos; [
      isolive
      airgap
      # not using cryptos from flake; micromanage dependencies
    ];
    environment.etc."issue".text = scriptCatalog.helpText;
    environment.interactiveShellInit = scriptContext.bash-make-gnupg-home;
    environment.systemPackages = scriptCatalog.packages;
  })
    ];
  };

  /**
  Comes with a helper script to destructively provision a bootable USB flashdrive formatted with an additional btrfs partition for manually managed persistance. The rationale for this is a backup strategy which bundles data with the tools needed to use it. Encrypted containers can be made on the persistant partition and the entire drive can be cloned for redundancy.

  > [!CAUTION]
  > ```
  > nix run .#mkbootable-cryptid -- /dev/sdX
  > ```

  Tip: use can use the following command to quickly enumerate removable blockdevices alongside their sizes.
  ```
  nix run nixpkgs#nushell -- -c "lsblk --json | from json | get blockdevices | where rm == true | select name size"
  ```
  */
  flake.apps.x86_64-linux.mkbootable-cryptid = {
    meta.description = "Write the cryptid ISO and persistent partition to a block device.";
    program =
      let
        name = "cryptid";
        iso = config.flake.nixosConfigurations.${name}.config.system.build.isoImage;
        pkgs = config.host.${name}.nixpkgs.legacyPackages.${config.host.${name}.system};
      in
      toString (config.flake.lib.mkIsoWriter {
        inherit name pkgs iso;
        postWrite = ''
          printf "\nAppending partition to %s ...\n" "$DEV"
          echo ", ,L" | sudo sfdisk --append --quiet "$DEV"
          sleep 1
          udevadm settle
          sleep 2

          LAST_PART=$(sudo partx -rgo NR "$DEV" | tail -1)
          printf "\nFormatting %s%s as btrfs...\n" "$DEV" "$LAST_PART"
          sudo ${pkgs.btrfs-progs}/bin/mkfs.btrfs -L "${persist-partition-label}" -f -m dup -d dup -M -q "''${DEV}''${LAST_PART}"
        '';
      });
  };
}
