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
    }
    {
      name = "cinny";
      module = nixos.serve-cinny;
      enabledConfig.homeserver = "example.test";
      # No discrete boolean activation surface: enabling it only builds a
      # package (serve.cinny.package), consumed by a domain composition.
      activationPaths = [ ];
      enabledAssertions = [ (config: {
        assertion = lib.isDerivation config.serve.cinny.package;
        message = "enabled Cinny did not produce its configured web artifact";
      }) ];
    }
    {
      name = "filebrowser";
      module = nixos.serve-filebrowser;
      activationPaths = [ [ "services" "filebrowser" "enable" ] ];
      enabledAssertions = [
        (mountOrdering "filebrowser" (config: config.serve.filebrowser.root))
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
    }
    {
      name = "jellyfin";
      module = nixos.serve-jellyfin;
      activationPaths = [ [ "services" "jellyfin" "enable" ] ];
      enabledAssertions = [
        (mountOrdering "jellyfin" (config: config.serve.jellyfin.libraryBuilder.source))
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
      serve.filebrowser.enable = true;
      serve.jellyfin.enable = true;
    }
  ];

  domainAssertions = [
    {
      assertion = jellyfinWithIdentity.services.jellyfin.user == "jellyfin"
        && jellyfinWithIdentity.users.users.jellyfin.isSystemUser
        && jellyfinWithIdentity.systemd.services.jellyfin.serviceConfig.ProtectHome;
      message = "Jellyfin must use its dedicated account and hide home directories even on an identified host";
    }
    {
      assertion = jellyfinCustomUser.services.jellyfin.user == "fixture-media"
        && !jellyfinCustomUser.systemd.services.jellyfin.serviceConfig.ProtectHome
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
      message = "domain-remotehost did not create the Filebrowser and Jellyfin routes";
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
