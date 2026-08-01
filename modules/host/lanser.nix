{ inputs, lib, ... }:
{
  host.lanser = {
    description = "Home server and public service host.";
    primaryUser = "user";
    stateVersion = "24.11";

    modules = (with inputs.self.modules.nixos; [
      nas
      ssh-host
      server-hardening
      headscale
      serve-caddy
      domain-0x04cc
      domain-remotehost
      serve-torrenting
    ])
    ++ [
      (
        { config, modulesPath, pkgs, ... }:
        let
          username = config.hostIdentity.primaryUser;
        in
        {
          imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

          boot = {
            initrd.availableKernelModules = [
              "xhci_pci"
              "ahci"
              "nvme"
              "usbhid"
              "usb_storage"
              "sd_mod"
            ];
            kernelModules = [
              "kvm-amd"
              "xt_policy"
              "exfat"
              "nfsv4"
            ];
            loader.grub = {
              enable = true;
              device = "/dev/nvme0n1";
              useOSProber = true;
            };
          };

          fileSystems = {
            "/" = {
              device = "/dev/disk/by-uuid/ad2633a1-749c-4f66-92ee-76f622fa5672";
              fsType = "ext4";
            };
            "/mnt/Services" = {
              device = "192.168.2.200:/mnt/Vault/Storage/services";
              fsType = "nfs";
              options = [
                "nfsvers=4.2"
                "x-systemd.automount"
                "noauto"
                "noatime"
              ];
            };
          };
          swapDevices = [
            { device = "/dev/disk/by-uuid/343255da-052c-4e75-88e5-381713edf427"; }
          ];

          networking = {
            enableIPv6 = false;
            useDHCP = false;
            wireless.enable = false;
            interfaces = {
              enp4s0.useDHCP = true;
              enp1s0 = { };
              enp1s0d1.ipv4.addresses = [
                {
                  address = "192.168.2.100";
                  prefixLength = 23;
                }
              ];
            };
            defaultGateway = {
              address = "172.16.0.1";
              interface = "enp4s0";
            };
            firewall = {
              allowedUDPPorts = [ 51820 ];
              checkReversePath = false;
            };
          };

          hardware.cpu.amd.updateMicrocode =
            lib.mkDefault config.hardware.enableRedistributableFirmware;

          services = {
            displayManager = {
              defaultSession = "lxqt";
              autoLogin = {
                enable = true;
                user = username;
              };
            };
            xserver = {
              enable = true;
              desktopManager.lxqt.enable = true;
              displayManager.lightdm.enable = true;
              xkb = {
                layout = "us";
                variant = "";
              };
            };
          };

          environment.systemPackages = with pkgs; [
            git
            openssh
            pinentry-tty
            btop
            iftop
            ghostty
            tmux
            home-manager
            p7zip
            unrar
            unar
            mozlz4a
            chromium
          ];

          programs.neovim = {
            enable = true;
            viAlias = true;
            vimAlias = true;
            defaultEditor = true;
          };

          users.users.${username} = {
            isNormalUser = true;
            description = username;
            extraGroups = [
              "networkmanager"
              "wheel"
            ];
          };

          ssh-host = {
            allowUsers = [ username ];
            hostKeyPath = "/etc/ssh/ssh_host_ed25519_key";
            comment = "lanser-hostkey";
          };

          nas = {
            server = "192.168.2.200";
            vault = {
              enable = true;
              readonly = true;
            };
            pocket.enable = true;
          };

          serve.headscale = {
            enable = true;
            adminAllowedCIDRs = [
              "192.168.2.0/23"
              "100.64.0.0/10"
            ];
          };

          services = {
            headscale.settings = {
              server_url = "https://headscale.0x04.cc";
              dns = {
                magic_dns = true;
                base_domain = "tailnet.0x04.cc";
                override_local_dns = true;
                nameservers.global = [
                  "1.1.1.1"
                  "1.0.0.1"
                ];
              };
              trusted_proxies = [ "127.0.0.1/32" ];
            };

            headplane.settings = {
              server.base_url = "https://headscale.0x04.cc";
              headscale.public_url = "https://headscale.0x04.cc";
            };
          };

          serve.caddy.bindAddress = "172.16.0.4";
        }
      )
    ];
  };
}
