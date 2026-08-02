{ inputs, lib, ... }:
{
  host.armatus = rec {
    description = "Laptop. Dell Precision 17 7720; 7820HQ+64GB, P5000+16GB, 512GB:NVMe.";
    primaryUser = "user";
    stateVersion = "26.11";
    capabilities.nixosAnywhere = true;

    userEnvironment.${primaryUser} = {
      mode = "integrated";
      profile = "workstation";
      preferences = "alaestor";
      modules = [
        (
          { pkgs, ... }:
          {
            home.packages = with pkgs; [
              keepassxc
            ];
          }
        )
      ];
    };

    modules = (with inputs.self.modules.nixos; [
      kde
      auto-login
      crypto-yubikey
      hifi-audio
      printers
      nas
      ssh-host
      standard-disk
    ])
    ++ [
      (
        { config, ... }:
        let
          username = config.hostIdentity.primaryUser;
        in
        {
          ssh-host = {
            allowUsers = [ username ];
            initrd.enable = true;
          };

          networking.networkmanager.enable = true;

          # Boot & Disks
          standard-disk.impermanence = {
            enable = false; #true;
            persist.users.${username}.directories = [ ".ssh" ];
          };

          /*nas = {
            cauldron.enable = true;
            vault.enable = true;
            pocket.enable = true;
            };*/

          # TODO(armatus): consider systemd-boot.enable = true;efi.canTouchEfiVariables = true;
          boot = {
            supportedFilesystems.btrfs = true;
            kernelModules = [ "kvm-intel" ];
            initrd.availableKernelModules = [ "e1000e" ];
            loader.grub = {
              efiSupport = true;
              efiInstallAsRemovable = true;
              device = "nodev";
            };
          };

          # GPU
          services.xserver.videoDrivers = [ "nvidia" ];
          hardware = {
            cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
            nvidia = {
              modesetting.enable = true;
              powerManagement.enable = true;
              open = false; # Pascal requires the proprietary kernel module
              package = config.boot.kernelPackages.nvidiaPackages.legacy_580; # P5000
              prime = {
                offload = {
                  enable = true;
                  enableOffloadCmd = true;
                };
                intelBusId = "PCI:0:2:0";
                nvidiaBusId = "PCI:1:0:0";
              };
            };
          };

          users.users.${username} = {
            isNormalUser = true;
            description = username;
            extraGroups = [
              "wheel"
              "systemd-journal"
            ];
            # Public bootstrap credential; replace it immediately after install.
            initialPassword = "changeme";
          };
        }
      )
    ];
  };
}
