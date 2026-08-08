{ inputs, ... }:
{
  # TODO(apc): debloat / simplify config.
  host.apc = rec {
    description = "APC desktop workstation.";
    primaryUser = "user";
    stateVersion = "24.05";

    userEnvironment.${primaryUser} = {
      mode = "standalone";
      modules = [
        inputs.self.modules.homeManager.workstation
        inputs.self.modules.homeManager.alaestor
        ../../hosts/apc/home/plasma.nix
        (
          { pkgs, ... }:
          let
            # TODO(pkgs): migrate ffmpeg-hdr
            ffmpeg-hdr =
              (pkgs.ffmpeg-headless.override {
                withUnfree = false;
                withTensorflow = false;
                withSmallBuild = false;
                withDebug = false;
                withSrt = false;
                withSsh = false;
                withRist = false;
                withGmp = false;
                withQrencode = false;
                withQuirc = false;
                withAom = false;
                withDav1d = false;
                withRav1e = false;
                withJxl = true;
                withSvtav1 = true;
                svt-av1 = pkgs.svt-av1-hdr;
              }).overrideAttrs
                (_: {
                  pname = "ffmpeg-hdr";
                });
          in
          {
            ssh-client.identityFiles = [
              "~/.ssh/ssh_sk"
              "~/.ssh/id_ed25519_apc"
            ];

            home = {
              stateVersion = "23.11";
              packages = with pkgs; [
                (bottles.override { removeWarningPopup = true; })
                veracrypt
                keepassxc
                btop-rocm
                iftop
                chromium
                tauon
                colordiff
                podman-compose
                #podman-tui
                mediainfo
                protonmail-desktop
                libreoffice-qt6-fresh
                obsidian
                discord
                webcord
                element-desktop
                jellyfin-desktop
                ffmpeg-hdr
                ripgrep
              ];
            };

            programs = {
              neovim = {
                enable = true;
                viAlias = true;
                vimAlias = true;
                defaultEditor = true;
                withPython3 = false;
                withRuby = false;
              };

              chromium = {
                enable = true;
                extensions = [
                  "gcbommkclmclpchllfjekcdonpmejbdp" # HTTPS Everywhere
                  "oboonakemofpalcgghocfoadofidjkkk" # KeePassXC-Browser
                ];
              };

              freetube = {
                enable = true;
                settings = {
                  useRssFeeds = true;
                  backendPreference = "local";
                  enableSearchSuggestions = false;
                  checkForBlogPosts = false;
                  checkForUpdates = false;
                  autoplayVideos = true;
                  defaultVolume = 0.5;
                  defaultPlayback = 2;
                  defaultQuality = "1080";
                  defaultTheatreMode = true;
                  maxVideoPlaybackRate = true;
                  videoPlaybackRateMouseScroll = true;
                  videoVolumeMouseScroll = true;
                  useSponsorBlock = true;
                  sponsorBlockIntro = {
                    color = "Orange";
                    skip = "autoSkip";
                  };
                  sponsorBlockMusicOffTopic = {
                    color = "Orange";
                    skip = "autoSkip";
                  };
                  sponsorBlockOutro = {
                    color = "Orange";
                    skip = "showInSeekBar";
                  };
                  baseTheme = "dark";
                  listType = "grid";
                  disableSmoothScrolling = true;
                  displayVideoPlayButton = false;
                  commentAutoLoadEnabled = false;
                  hideHeaderLogo = true;
                  hidePopularVideos = true;
                  hideTrendingVideos = true;
                  hideActiveSubscriptions = true;
                  enableScreenshot = true;
                  screenshotFormat = "jpg";
                  screenshotQuality = 85;
                };
              };
            };

            xdg = {
              enable = true;
              configFile."mimeapps.list".force = true;
              mimeApps = {
                enable = true;
                defaultApplications = {
                  "text/html" = "librewolf.desktop";
                  "x-scheme-handler/http" = "librewolf.desktop";
                  "x-scheme-handler/https" = "librewolf.desktop";
                  "x-scheme-handler/about" = "librewolf.desktop";
                  "x-scheme-handler/unknown" = "librewolf.desktop";
                };
              };
            };
          }
        )
      ];
    };

    modules =
      (with inputs.self.modules.nixos; [
        auto-login
        crypto-yubikey
        hifi-audio
        kde
        nas
        printers
        serve-nix-cache
        ssh-client
        ssh-host
        tailnet-client
      ])
      ++ [
        (
          {
            config,
            lib,
            modulesPath,
            pkgs,
            ...
          }:
          let
            username = config.hostIdentity.primaryUser;
            secretPath = inputs.self.secrets.path;
          in
          {
            imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

            age = {
              identityPaths = [ config.ssh-host.hostKeyPath ];
              secrets = {
                apc-wireguard-private-key = {
                  file = secretPath "vpn_APC-GT-18_key.age";
                  mode = "0400";
                };
              };
            };

            crypto-yubikey.administrativeStubs.enable = true;

            serve.nix-cache.enable = true;

            ssh-host.authorizedKeys = [ inputs.self.data.vars.sshClientPublicKeys.noblesse ];

            boot = {
              binfmt.emulatedSystems = [ "aarch64-linux" ]; # to cross-compile for noblesse
              kernelPackages = pkgs.linuxPackages_latest;
              initrd = {
                availableKernelModules = [
                  "nvme"
                  "xhci_pci"
                  "ahci"
                  "usb_storage"
                  "usbhid"
                  "sd_mod"
                ];
                luks.devices = {
                  "luks-98abcfc9-20d2-4af9-ac5f-09c72359086e".device =
                    "/dev/disk/by-uuid/98abcfc9-20d2-4af9-ac5f-09c72359086e";
                  "luks-9fd45c42-514d-47e6-975c-88e6e8bafec3".device =
                    "/dev/disk/by-uuid/9fd45c42-514d-47e6-975c-88e6e8bafec3";
                };
              };
              kernelModules = [
                "amdgpu"
                "dns_resolver"
                "kvm-amd"
                "nfsv4"
                "exfat"
                "ntfs3"
                "rpcsec_gss_krb5"
                "qrtr"
                "snd_hrtimer"
                "snd_seq"
                "snd_seq_dummy"
                "xt_policy"
              ];
              kernelParams = [
                "slab_nomerge"
                "page_position=1"
                "page_alloc.shuffle=1"
                "debugfs=off"
              ];
              blacklistedKernelModules = [
                "ax25"
                "netrom"
                "rose"
                "adfs"
                "affs"
                "bfs"
                "befs"
                "cramfs"
                "efs"
                "erofs"
                "exofs"
                "freevxfs"
                "f2fs"
                "hfs"
                "hpfs"
                "jfs"
                "minix"
                "nilfs2"
                "omfs"
                "qnx4"
                "qnx6"
                "sysv"
                "ufs"
              ];
              kernel.sysctl = {
                "kernel.kptr_restrict" = lib.mkOverride 500 2;
                "net.core.bpf_jit_enable" = false;
                "kernel.ftrace_enabled" = false;
                "net.ipv4.conf.all.log_martians" = true;
                "net.ipv4.conf.all.rp_filter" = "1";
                "net.ipv4.conf.default.log_martians" = true;
                "net.ipv4.conf.default.rp_filter" = "1";
                "net.ipv4.icmp_echo_ignore_broadcasts" = true;
                "net.ipv4.conf.all.accept_redirects" = lib.mkDefault false;
                "net.ipv4.conf.all.secure_redirects" = lib.mkDefault false;
                "net.ipv4.conf.default.accept_redirects" = lib.mkDefault false;
                "net.ipv4.conf.default.secure_redirects" = lib.mkDefault false;
                "net.ipv6.conf.all.accept_redirects" = lib.mkDefault false;
                "net.ipv6.conf.default.accept_redirects" = lib.mkDefault false;
                "net.ipv4.conf.all.send_redirects" = false;
                "net.ipv4.conf.default.send_redirects" = false;
                "net.ipv6.conf.all.accept_ra" = 0;
                "net.ipv6.conf.default.accept_ra" = 0;
              };
              loader = {
                systemd-boot.enable = true;
                efi.canTouchEfiVariables = true;
              };
            };

            fileSystems = {
              "/" = {
                device = "/dev/disk/by-uuid/b8d36e54-a050-4606-b99b-b169a732c561";
                fsType = "ext4";
              };
              "/boot" = {
                device = "/dev/disk/by-uuid/D817-CBDF";
                fsType = "vfat";
                options = [
                  "fmask=0022"
                  "dmask=0022"
                ];
              };
            };

            environment = {
              sessionVariables.NIXOS_OZONE_WL = "1";
              systemPackages = with pkgs; [
                pinentry-tty
                wl-clipboard-rs
                xkill
                nfs-utils
                p7zip
                unrar
                unar
                lzip
                mozlz4a
                kdePackages.kgpg
                kdePackages.ksystemlog
                kdePackages.partitionmanager
                kdePackages.xdg-desktop-portal-kde
              ];
            };

            fonts.packages = builtins.filter lib.attrsets.isDerivation (builtins.attrValues pkgs.nerd-fonts);

            hardware = {
              cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
              graphics = {
                enable = true;
                enable32Bit = true;
                extraPackages = [ pkgs.rocmPackages.clr.icd ];
              };
              gpgSmartcards.enable = true;
            };

            # TODO(apc): yeet nix.settings (is @wheel even needed?)
            nix.settings = {
              auto-optimise-store = true;
              download-buffer-size = 524288000 * 2; # TODO(global): download-buffer-size
              experimental-features = [
                "nix-command"
                "flakes"
              ];
              allowed-users = [ "@wheel" ];
            };

            networking = {
              domain = "tailnet.0x04.cc";
              enableIPv6 = true;
              networkmanager.enable = true;
              useDHCP = false;
              interfaces = {
                enp34s0.useDHCP = true;
                enp42s0 = { };
              };
              defaultGateway = {
                address = "172.16.0.1"; # TODO(lan): state: gateway
                interface = "enp34s0";
              };
              wg-quick.interfaces.wg0 = {
                table = "100";
                address = [ "10.2.0.2/32" ];
                privateKeyFile = config.age.secrets.apc-wireguard-private-key.path;
                postUp = ''
                  ip rule add from 10.2.0.2/32 table 100
                  ip rule add to 89.238.174.2 lookup main priority 100
                '';
                preDown = ''
                  ip rule del from 10.2.0.2/32 table 100
                  ip rule del to 89.238.174.2 lookup main priority 100
                '';
                peers = [
                  {
                    publicKey = "UBnjj4fW9ZR7bGnxN7JOD9G9AOwkYWl2gADZRHljEHI=";
                    allowedIPs = [
                      "0.0.0.0/0"
                      "::/0"
                    ];
                    endpoint = "89.238.174.2:51820";
                    persistentKeepalive = 25;
                  }
                ];
              };
              hosts = { # TODO(apc):  del dumb fake dns
                "172.16.0.1" = [ "router.lan" ];
                "192.168.1.200" = [ "NAS" ];
              };
              # TODO(apc): make a gaming aspect and move this into a steam module
              extraHosts = "0.0.0.0 crash.steampowered.com";
              firewall = {
                enable = lib.mkForce true;
                allowPing = false;
                trustedInterfaces = [ "vmtap2" ];
                allowedTCPPorts = [
                  1234
                  2234
                ];
              };
            };

            nas = {
              server = "172.16.0.2"; # TODO(lan): nas ip
              cauldron.enable = true;
              vault.enable = true;
              pocket.enable = true;
            };

            programs = {
              steam = {
                enable = true;
                remotePlay.openFirewall = true;
              };
              virt-manager.enable = true;
            };

            security = {
              lockKernelModules = false;
              protectKernelImage = true;
              forcePageTableIsolation = true;
              virtualisation.flushL1DataCache = "always";
              sudo.enable = false;
              sudo-rs = {
                enable = true;
                package = pkgs.sudo-rs;
                execWheelOnly = true;
              };
              apparmor = {
                enable = true;
                killUnconfinedConfinables = true;
              };
            };

            services = {
              earlyoom = {
                enable = true;
                enableNotifications = true;
              };
              ratbagd = {
                enable = true;
                package = pkgs.libratbag;
              };
              avahi.enable = lib.mkForce false;
              printing = {
                browsed.enable = lib.mkForce false;
                browsing = lib.mkForce false;
              };
            };

            systemd = {
              oomd.enable = false; # TODO: oomd + earlyoomkiller module (or just global?)
              # TODO(apc): legacy rocm hip rule; still needed?
              tmpfiles.rules = [
                "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
              ];
               # TODO(apc): make a gaming aspect and move this into a steam module
              user.services.preventSteamDumps = {
                description = "Symlink Steam crash reports to /dev/null";
                script = "ln -s /dev/null /tmp/dumps";
                wantedBy = [ "multi-user.target" ];
              };
            };

            users.users.${username} = {
              isNormalUser = true;
              description = username;
              extraGroups = [
                "networkmanager"
                "wheel"
                "kvm"
                "ydotool"
                "input"
                "uinput"
              ];
            };

            virtualisation = {
              libvirtd.enable = true;
              podman = {
                enable = true;
                dockerCompat = true;
              };
            };

            xdg.portal.enable = true;
            zramSwap = {
              enable = true;
              memoryPercent = 30;
            };
          }
        )
      ];
  };
}
