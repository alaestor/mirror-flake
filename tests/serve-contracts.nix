{
  inputs,
  pkgs,
  system,
  ...
}:
let
  lib = inputs.nixpkgs.lib;
  harness = import ./lib/serve-contract.nix { inherit inputs system; };
  nixos = inputs.self.modules.nixos;
  # Exercise cache admission without depending on a personal encrypted key.
  # This substitutes only the source-key existence probe, not the service.
  cacheModule = exists: (import "${inputs.self}/modules/serve/services/nix-cache.nix" {
    inherit inputs;
    self = inputs.self // {
      secrets = inputs.self.secrets // {
        nixStoreSigning = _: { inherit exists; subpath = "fixture-signing-key.age"; };
      };
    };
  }).flake.modules.nixos.serve-nix-cache;
  cacheWithoutKey = harness.evaluate [
    (cacheModule false)
    { serve.nix-cache = { enable = true; authority = "cache.example.test"; }; }
  ];
  cacheWithKey = harness.evaluate [
    (cacheModule true)
    { serve.nix-cache = { enable = true; authority = "cache.example.test"; }; }
  ];

  forgejoWithNas = harness.evaluate [
    nixos.serve-forgejo
    nixos.nas
    nixos.user-environment
    {
      nas.services.mountpoint = "/mnt/fixture-nas";
      serve.forgejo = { enable = true; domain = "git.example.test"; };
    }
  ];
  forgejoCustomRoot = harness.evaluate [
    nixos.serve-forgejo
    {
      serve.forgejo = {
        enable = true;
        domain = "git.example.test";
        dataRoot = "/srv/fixture-forgejo";
      };
    }
  ];

  jellyfinWithIdentity = harness.evaluate [
    nixos.serve-jellyfin
    ({ lib, ... }: {
      options.hostIdentity = lib.mkOption { type = lib.types.attrs; };
      config = {
        hostIdentity.primaryUser = "fixture-admin";
        serve.jellyfin.enable = true;
      };
    })
  ];
  jellyfinCustomUser = harness.evaluate [
    nixos.serve-jellyfin
    {
      serve.jellyfin = {
        enable = true;
        user = "fixture-media";
        libraryBuilder.enable = false;
      };
      systemd.services.jellyfin.serviceConfig.ProtectHome = false;
    }
  ];

  filebrowserCustomPaths = harness.evaluate [
    nixos.serve-filebrowser
    {
      serve.filebrowser = { enable = true; root = "/srv/fixture-media"; };
      services.filebrowser.settings.database = "/srv/fixture-filebrowser/database.db";
    }
  ];
  jellyfinCustomPaths = harness.evaluate [
    nixos.serve-jellyfin
    {
      serve.jellyfin = {
        enable = true;
        libraryBuilder.source = "/srv/fixture-media";
      };
      services.jellyfin = {
        dataDir = "/srv/fixture-jellyfin/data";
        configDir = "/srv/fixture-jellyfin/config";
        cacheDir = "/srv/fixture-jellyfin/cache";
        logDir = "/srv/fixture-jellyfin/log";
        hardwareAcceleration = { enable = true; device = "/dev/dri/renderD129"; };
      };
    }
  ];
  torrentingCustomPaths = harness.evaluate [
    nixos.serve-torrenting
    {
      serve.torrenting = { enable = true; downloadPath = "/srv/fixture-downloads"; };
      services.qbittorrent.profileDir = "/srv/fixture-qbittorrent";
    }
  ];

  # A service whose data root can sit on a network share must order itself
  # against that mount, or shutdown tries to unmount the share out from under
  # a service still holding files open on it.
  mountOrdering =
    unit: getPath: config: {
      assertion = lib.elem (getPath config) (
        lib.attrByPath [ "systemd" "services" unit "unitConfig" "RequiresMountsFor" ] [ ] config
      );
      message = "${unit} does not require the mount holding its data root";
    };

  cases = [
    {
      name = "caddy";
      module = nixos.serve-caddy;
      activationPaths = [ [ "services" "caddy" "enable" ] ];
      enabledAssertions = [ (config: {
        assertion = with config.systemd.services.caddy.serviceConfig;
          ProtectSystem == "strict" && lib.elem "/run" ReadOnlyPaths
          && lib.elem config.services.caddy.dataDir ReadWritePaths
          && lib.elem config.services.caddy.logDir ReadWritePaths
          && lib.elem "/run/caddy" ReadWritePaths
          && RuntimeDirectory == [ "caddy" ] && RuntimeDirectoryMode == "0700"
          && AmbientCapabilities == [ "" "CAP_NET_BIND_SERVICE" ]
          && CapabilityBoundingSet == [ "CAP_NET_BIND_SERVICE" ];
        message = "Caddy must restrict filesystem writes and retain only low-port binding capability";
      }) ];
    }
    {
      name = "dufs";
      module = nixos.serve-dufs;
      activationPaths = [ [ "services" "dufs" "enable" ] [ "security" "apparmor" "enable" ] ];
      enabledConfig = {
        authFile = "/run/secrets/fixture-dufs.env";
        shares = { Films = "/srv/fixture-films"; Audio = "/srv/fixture-audio"; };
      };
      enabledAssertions = [
        (mountOrdering "dufs" (_: "/srv/fixture-films"))
        (mountOrdering "dufs" (_: "/srv/fixture-audio"))
        (config: {
          assertion = with config.systemd.services.dufs.serviceConfig;
            RootDirectory == "/run/dufs-root"
            && ProtectSystem == "strict" && ProtectHome && PrivateTmp
            && ReadWritePaths == [ ] && ReadOnlyPaths == [ "+/run" ]
            && BindReadOnlyPaths == [ builtins.storeDir "/srv/fixture-audio:/media/Audio" "/srv/fixture-films:/media/Films" ]
            && EnvironmentFile == [ "/run/secrets/fixture-dufs.env" ]
            && AppArmorProfile == "serve-dufs"
            && config.security.apparmor.enable
            && config.security.apparmor.policies.serve-dufs.state == "enforce"
            && config.systemd.services.dufs.unitConfig.AssertSecurity == "apparmor"
            && builtins.elem "apparmor.service" config.systemd.services.dufs.requires
            && builtins.elem "apparmor.service" config.systemd.services.dufs.after
            && config.services.dufs.bindAddresses == [ "127.0.0.1" ]
            && config.services.dufs.settings.allow-search
            && config.services.dufs.settings.allow-archive
            && !config.services.dufs.settings.allow-upload
            && !config.services.dufs.settings.allow-delete;
          message = "Dufs must expose only selected read-only shares, require runtime accounts, and keep its listener private";
        })
      ];
    }
    {
      name = "filebrowser";
      module = nixos.serve-filebrowser;
      activationPaths = [ [ "services" "filebrowser" "enable" ] ];
      enabledAssertions = [
        (mountOrdering "filebrowser" (config: config.serve.filebrowser.root))
        (config: {
          assertion = with config.systemd.services.filebrowser.serviceConfig;
            ProtectSystem == "strict" && ProtectHome && PrivateTmp
            && lib.elem "/run" ReadOnlyPaths && lib.elem config.serve.filebrowser.root ReadOnlyPaths
            && !(lib.elem config.serve.filebrowser.root ReadWritePaths);
          message = "Filebrowser must protect the host filesystem and keep media read-only";
        })
      ];
    }
    {
      name = "forgejo";
      module = nixos.serve-forgejo;
      activationPaths = [ [ "services" "forgejo" "enable" ] ];
      enabledConfig.domain = "git.example.test";
      enabledAssertions = [
        (mountOrdering "forgejo" (config: config.serve.forgejo.dataRoot))
        (mountOrdering "forgejo-secrets" (config: config.serve.forgejo.dataRoot))
        (config: {
          assertion = config.serve.forgejo.dataRoot == "/var/lib/forgejo"
            && config.services.forgejo.stateDir == "/var/lib/forgejo/state"
            && config.services.forgejo.lfs.contentDir == "/var/lib/forgejo/lfs";
          message = "Forgejo does not default to local state and LFS storage";
        })
        (config: {
          assertion = !(config.environment.etc ? "ssh/authorized_keys_command_forgejo")
            && !(lib.hasInfix "AuthorizedKeysCommand" config.services.openssh.extraConfig)
            && builtins.all (unit: !(lib.elem "nas-detach.service" config.systemd.services.${unit}.after))
              [ "forgejo" "forgejo-secrets" ];
          message = "Forgejo installs host-specific NAS or SSH workarounds";
        })
      ];
    }
    {
      name = "headscale";
      module = nixos.serve-headscale;
      activationPaths = [
        [ "services" "headscale" "enable" ]
        [ "services" "headplane" "enable" ]
      ];
      enabledAssertions = [
        (config: {
          assertion = with config.systemd.services.headplane.serviceConfig;
            User == "headplane" && Group == "headplane"
            && User != config.services.headscale.user
            && ProtectSystem == "strict" && ProtectHome && PrivateTmp
            && lib.elem "/run" ReadOnlyPaths
            && lib.elem "/var/lib/headscale" InaccessiblePaths
            && !config.services.headplane.settings.integration.proc.enabled;
          message = "Headplane must isolate its account and filesystem without Headscale process control";
        })
      ];
    }
    {
      name = "jellyfin";
      module = nixos.serve-jellyfin;
      activationPaths = [ [ "services" "jellyfin" "enable" ] ];
      enabledAssertions = [
        (mountOrdering "jellyfin" (config: config.serve.jellyfin.libraryBuilder.source))
        (config: {
          assertion = with config.systemd.services.jellyfin.serviceConfig;
            ProtectSystem == "strict" && DevicePolicy == "closed"
            && lib.elem "/run" ReadOnlyPaths && lib.elem config.serve.jellyfin.libraryBuilder.source ReadOnlyPaths
            && !(lib.elem config.serve.jellyfin.libraryBuilder.source ReadWritePaths);
          message = "Jellyfin must protect the host filesystem, keep media read-only, and restrict devices";
        })
      ];
    }
    {
      name = "matrix";
      module = nixos.serve-matrix;
      activationPaths = [ [ "services" "matrix-tuwunel" "enable" ] ];
      enabledConfig.serverName = "example.test";
    }
    {
      name = "nix-cache";
      module = cacheModule true;
      activationPaths = [ [ "services" "nix-serve" "enable" ] ];
      enabledConfig.authority = "cache.example.test";
      enabledAssertions = [ (config: {
        assertion = config.networking.firewall.interfaces.tailscale0.allowedTCPPorts == [ config.serve.nix-cache.port ];
        message = "enabled cache did not restrict its ingress to the private interface";
      }) ];
    }
    {
      name = "torrenting";
      module = nixos.serve-torrenting;
      activationPaths = [ [ "services" "qbittorrent" "enable" ] ];
      enabledAssertions = [
        (mountOrdering "qbittorrent" (config: config.serve.torrenting.downloadPath))
        (config: {
          assertion = with config.systemd.services.qbittorrent.serviceConfig;
            ProtectSystem == "strict" && PrivateTmp && lib.elem "/run" ReadOnlyPaths
            && ReadWritePaths == [ config.services.qbittorrent.profileDir config.serve.torrenting.downloadPath ];
          message = "qBittorrent must restrict writes to its profile, downloads, and private temporary files";
        })
      ];
    }
  ];

  serviceAssertions = lib.concatMap harness.serviceCase cases;

  domainDisabled = harness.evaluate [ nixos.domain-0x04 ];
  domainStatic = harness.evaluate [
    nixos.domain-0x04
    { serve.static-site-0x04 = { enable = true; root = "/srv/site-fixture"; }; }
  ];
  domainHeadscale = harness.evaluate [
    nixos.domain-0x04
    { serve.headscale.enable = true; }
  ];
  domainMatrix = harness.evaluate [
    nixos.domain-0x04
    { serve.matrix.enable = true; }
  ];

  bokunopiDisabled = harness.evaluate [ nixos.domain-bokunopi ];
  bokunopiEnabled = harness.evaluate [
    nixos.domain-bokunopi
    { serve.static-site-bokunopi = { enable = true; root = "/srv/other-site-fixture"; }; }
  ];

  remotehostDisabled = harness.evaluate [ nixos.domain-remotehost ];
  remotehostEnabled = harness.evaluate [
    nixos.domain-remotehost
    {
      serve.dufs = {
        enable = true;
        authFile = "/run/secrets/fixture-dufs.env";
        shares.Films = "/srv/fixture-films";
      };
      serve.jellyfin.enable = true;
    }
  ];

  domainAssertions = [
    {
      assertion = with filebrowserCustomPaths.systemd.services.filebrowser.serviceConfig;
        ReadWritePaths == [ "/srv/fixture-filebrowser" ]
        && ReadOnlyPaths == [ "/run" "/srv/fixture-media" ]
        && StateDirectory == "filebrowser" && CacheDirectory == "filebrowser";
      message = "Filebrowser must derive write exceptions from its database and preserve managed state/cache directories";
    }
    {
      assertion = with jellyfinCustomPaths.systemd.services.jellyfin.serviceConfig;
        ReadWritePaths == [
          "/srv/fixture-jellyfin/data" "/srv/fixture-jellyfin/config"
          "/srv/fixture-jellyfin/cache" "/srv/fixture-jellyfin/log"
        ]
        && ReadOnlyPaths == [ "/run" "/srv/fixture-media" ]
        && DevicePolicy == "closed" && lib.elem "/dev/dri/renderD129 rw" DeviceAllow;
      message = "Jellyfin must follow custom application paths and retain explicitly allowed acceleration devices";
    }
    {
      assertion = torrentingCustomPaths.systemd.services.qbittorrent.serviceConfig.ReadWritePaths
        == [ "/srv/fixture-qbittorrent" "/srv/fixture-downloads" ];
      message = "qBittorrent must follow custom profile and download paths";
    }
    {
      assertion = jellyfinWithIdentity.services.jellyfin.user == "jellyfin"
        && jellyfinWithIdentity.users.users.jellyfin.isSystemUser
        && jellyfinWithIdentity.systemd.services.jellyfin.serviceConfig.ProtectHome;
      message = "Jellyfin must use its dedicated account and hide home directories even on an identified host";
    }
    {
      assertion = jellyfinCustomUser.services.jellyfin.user == "fixture-media"
        && !jellyfinCustomUser.systemd.services.jellyfin.serviceConfig.ProtectHome
        && jellyfinCustomUser.systemd.services.jellyfin.serviceConfig.ReadOnlyPaths == [ "/run" ]
        && !(lib.elem "nas-detach.service" jellyfinCustomUser.systemd.services.jellyfin.after)
        && !(lib.elem "/mnt/Vault/Media" jellyfinCustomUser.systemd.services.jellyfin.unitConfig.RequiresMountsFor);
      message = "Jellyfin must allow explicit account/home refinements and omit library mount dependencies when disabled";
    }
    {
      assertion = forgejoWithNas.serve.forgejo.dataRoot == "/var/lib/forgejo";
      message = "Importing NAS changes Forgejo's storage placement";
    }
    {
      assertion = forgejoCustomRoot.services.forgejo.stateDir == "/srv/fixture-forgejo/state"
        && forgejoCustomRoot.services.forgejo.lfs.contentDir == "/srv/fixture-forgejo/lfs"
        && builtins.all (unit:
          lib.elem "/srv/fixture-forgejo" forgejoCustomRoot.systemd.services.${unit}.unitConfig.RequiresMountsFor
        ) [ "forgejo" "forgejo-secrets" ];
      message = "Forgejo ignores the configured data root for state, LFS, or mount dependencies";
    }
    {
      assertion = !cacheWithoutKey.services.nix-serve.enable
        && cacheWithoutKey.networking.firewall.interfaces.tailscale0.allowedTCPPorts == [ ]
        && builtins.any (lib.hasInfix "nix-serve was not enabled") cacheWithoutKey.warnings;
      message = "cache without a signing key must stay closed and warn rather than serve unsigned paths";
    }
    {
      assertion = domainDisabled.services.caddy.virtualHosts == { };
      message = "domain-0x04cc creates routes with all members disabled";
    }
    {
      assertion = domainDisabled.networking.firewall.allowedTCPPorts == [ ];
      message = "domain-0x04cc opens public ingress with all members disabled";
    }
    {
      assertion = builtins.attrNames domainStatic.services.caddy.virtualHosts == [ "0x04.cc" ]
        && lib.hasInfix "root * /srv/site-fixture" domainStatic.services.caddy.virtualHosts."0x04.cc".extraConfig
        && domainStatic.networking.firewall.allowedTCPPorts == [ 80 443 ];
      message = "domain-0x04cc did not expose only the configured static content root";
    }
    {
      assertion = builtins.attrNames domainHeadscale.services.caddy.virtualHosts == [ "headscale.0x04.cc" ];
      message = "domain-0x04cc did not create only the Headscale route";
    }
    {
      assertion = domainHeadscale.networking.firewall.allowedTCPPorts == [ 80 443 ];
      message = "domain-0x04cc Headscale ingress differs from ports 80 and 443";
    }
    {
      assertion = domainHeadscale.services.headscale.settings.server_url == "https://headscale.0x04.cc"
        && (domainHeadscale.services.headplane.settings.server.base_url or null) == "https://headscale.0x04.cc"
        && (domainHeadscale.services.headplane.settings.headscale.public_url or null) == "https://headscale.0x04.cc";
      message = "domain-0x04 did not configure the public URLs for Headscale and Headplane";
    }
    {
      assertion = (domainDisabled.services.headscale.settings.server_url or null) != "https://headscale.0x04.cc"
        && (domainDisabled.services.headplane.settings.server.base_url or null) != "https://headscale.0x04.cc"
        && (domainDisabled.services.headplane.settings.headscale.public_url or null) != "https://headscale.0x04.cc";
      message = "domain-0x04 configures Headscale public URLs while the service is disabled";
    }
    {
      assertion = domainMatrix.services.matrix-tuwunel.enable;
      message = "domain-0x04cc did not configure Matrix when enabled";
    }
    {
      assertion = domainMatrix.networking.firewall.allowedTCPPorts == [ 80 443 8448 ];
      message = "domain-0x04cc Matrix ingress differs from ports 80, 443, and 8448";
    }
    {
      assertion = bokunopiDisabled.services.caddy.virtualHosts == { };
      message = "domain-bokunopi creates routes with all members disabled";
    }
    {
      assertion = bokunopiDisabled.networking.firewall.allowedTCPPorts == [ ];
      message = "domain-bokunopi opens public ingress with all members disabled";
    }
    {
      assertion = builtins.attrNames bokunopiEnabled.services.caddy.virtualHosts == [ "bokunopi.co" ];
      message = "domain-bokunopi did not create only the static-site route";
    }
    {
      assertion = lib.hasInfix "root * /srv/other-site-fixture"
        bokunopiEnabled.services.caddy.virtualHosts."bokunopi.co".extraConfig;
      message = "domain-bokunopi ignored its host's static content root";
    }
    {
      assertion = bokunopiEnabled.networking.firewall.allowedTCPPorts == [ 80 443 ];
      message = "domain-bokunopi ingress differs from ports 80 and 443";
    }
    {
      assertion = remotehostDisabled.services.caddy.virtualHosts == { };
      message = "domain-remotehost creates routes with all members disabled";
    }
    {
      assertion = remotehostDisabled.networking.firewall.allowedTCPPorts == [ ];
      message = "domain-remotehost opens public ingress with all members disabled";
    }
    {
      assertion = builtins.attrNames remotehostEnabled.services.caddy.virtualHosts == [
        "jellyfin.remotehost.cc, jellyfin.remotehost.cc:44344, shota.zip, shota.zip:44344"
        "media.remotehost.cc"
      ];
      message = "domain-remotehost did not create the Dufs and Jellyfin routes";
    }
    {
      assertion = remotehostEnabled.networking.firewall.allowedTCPPorts == [ 80 443 44344 ];
      message = "domain-remotehost ingress differs from ports 80, 443, and 44344";
    }
  ];

  failures = map (result: result.message) (
    builtins.filter (result: !result.assertion) (serviceAssertions ++ domainAssertions)
  );
in
pkgs.runCommand "serve-contracts-test"
  {
    nativeBuildInputs = [ pkgs.curl ];
    passAsFile = [ "failureReport" ];
    failureReport = builtins.concatStringsSep "\n" failures;
  }
  ''
    if [[ -s "$failureReportPath" ]]; then
      cat "$failureReportPath" >&2
      exit 1
    fi

    # Exercise the selected implementation with the NixOS module's CLI syntax.
    # A dummy store keeps this independent of the build machine's daemon/keys.
    export NIX_REMOTE=dummy://
    ${lib.getExe cacheWithKey.services.nix-serve.package} --listen 127.0.0.1:15000 > server.log 2>&1 &
    server_pid=$!
    trap 'kill "$server_pid" 2>/dev/null || true; wait "$server_pid" || true' EXIT
    if ! curl --fail --silent --show-error --noproxy '*' \
      --retry 10 --retry-connrefused --retry-delay 1 --retry-max-time 15 --max-time 2 \
      http://127.0.0.1:15000/nix-cache-info > cache-info; then
      cat server.log >&2
      exit 1
    fi
    grep -Fx 'StoreDir: ${builtins.storeDir}' cache-info
    grep -Fx 'WantMassQuery: 1' cache-info
    touch "$out"
  ''
