/**

Declarative registry for the hosts in this flake.
Each host is defined as an attribute in `config.host`, declares the module
`class` it is evaluated in, and automatically produces:
 - A NixOS configuration under `flake.nixosConfigurations`, or a Nix-on-Droid
   configuration under `flake.nixOnDroidConfigurations`
 - Optional helper apps (ISO writer, nixos-anywhere deployer)

Every generated configuration is pre-composed with the `host-identity` module
of its class, so that each host inherits a consistent identity; NixOS hosts
additionally inherit the common `global-config` base settings.

Hosts may also attach Home Manager environments under `userEnvironment`.
Feature-contributed and explicitly attached modules are composed identically for
integrated, standalone, and Nix-on-Droid activation.

*/
{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;

  # Nix-on-Droid owns one Android account whose home directory is a read-only
  # platform fact; a mismatch here must surface as a definition conflict.
  nixOnDroidHomeDirectory = "/data/data/com.termux.nix/files/home";

  # Host and user-environment option schema.
  userEnvironmentModule =
    { lib, ... }:
    {
      options.userEnvironment.sharedModules = lib.mkOption {
        type = lib.types.listOf lib.types.deferredModule;
        default = [ ];
        description = "Home Manager modules contributed by this host's platform features.";
      };
    };

  userEnvironmentType =
    class:
    types.submodule (
      { name, ... }:
      {
        options = {
          mode = mkOption {
            type = types.enum (
              [ "integrated" ] ++ lib.optional (class == "nixos") "standalone"
            );
            description = "Whether this user environment is activated with its host system or independently. Only NixOS hosts support standalone activation.";
          };

          homeDirectory = mkOption {
            type = types.nonEmptyStr;
            # nixOnDroid: read-only, so a host that tries to override this
            # platform fact gets a definition-conflict error instead of the
            # mismatch only ever surfacing (if at all) deep inside
            # Nix-on-Droid's own modules.
            readOnly = class == "nixOnDroid";
            default =
              if class == "nixOnDroid" then
                nixOnDroidHomeDirectory
              else if name == "root" then
                "/root"
              else
                "/home/${name}";
            defaultText = lib.literalExpression ''"/home/\${name}", or the platform-owned home directory'';
            description = "The user's home directory on this host.";
          };

          modules = mkOption {
            type = types.listOf types.deferredModule;
            default = [ ];
            description = "Host-and-user-specific Home Manager modules.";
          };
        };
      }
    );

  /**
    Provides a per-host option schema to configure options related to
    hostIdentity, along with nixpkgs, system, and modules.
  */
  hostType = types.submodule (
    { config, ... }:
    {
    options = {

      class = mkOption {
        type = types.enum [
          "nixos"
          "nixOnDroid"
        ];
        default = "nixos";
        description = "The module class in which this host is evaluated. It selects both the configuration builder and the namespace from which this host's modules are drawn.";
      };

      system = mkOption {
        type = types.str;
        default = "x86_64-linux";
        description = "The Nix system used to evaluate this host.";
      };

      nixpkgs = mkOption {
        type = types.raw;
        default = inputs.unstable-nixpkgs;
        description = "The nixpkgs flake used to evaluate this host.";
      };

      description = mkOption {
        type = types.nonEmptyStr;
        description = "A human-readable description of this host.";
      };

      primaryUser = mkOption {
        type = types.nonEmptyStr;
        description = "The primary interactive user of this host.";
      };

      stateVersion = mkOption {
        type = types.nonEmptyStr;
        description = "The required NixOS compatibility state version, also used as the default Home Manager state version. Set it when a host is first installed; change it only for an intentional fresh-install baseline, not during an in-place update.";
      };

      modules = mkOption {
        type = types.listOf types.deferredModule;
        default = [ ];
        description = "The modules of this host's declared class which define it.";
      };

      homeManager = {
        channel = mkOption {
          type = types.enum [
            "stable"
            "unstable"
          ];
          default = "unstable";
          description = "The Home Manager input used for this host's user environments.";
        };

        flake = mkOption {
          type = types.raw;
          default =
            if config.homeManager.channel == "stable" then
              inputs.stable-home-manager
            else
              inputs.unstable-home-manager;
          defaultText = lib.literalExpression "the Home Manager input named by `homeManager.channel`";
          description = "The Home Manager flake used for this host's user environments. Override it only when a host's platform requires a Home Manager release that is not one of the repository channels.";
        };
      };

      nixOnDroid.bootstrapSystem = mkOption {
        type = types.str;
        default = config.system;
        defaultText = lib.literalExpression "config.system";
        description = "The system on which a Nix-on-Droid host's bootstrap is built. Set it to cross-compile from a build host.";
      };

      userEnvironment = mkOption {
        type = types.attrsOf (userEnvironmentType config.class);
        default = { };
        description = "User environments deployed to this host.";
      };

      /**
        Set host configuration capabilities such as enabling the `nix run`
        `deploy` nixosAnywhere scripts, or `mkBootable` ISO scripts. These
        helper outputs are generated for NixOS hosts only.
      */
      capabilities = {

        isoWriter = mkOption {
          type = types.either types.bool (
            types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = false;
                  description = "Whether to generate a standard ISO writer app for this host.";
                };
                postWrite = mkOption {
                  type = types.lines;
                  default = "";
                  description = "Shell commands run after the ISO image is written to the block device, e.g. to append and format an additional persistence partition.";
                };
              };
            }
          );
          default = false;
          description = "Whether to generate a standard ISO writer app for this host. Pass `true`/`false` for the plain case, or a submodule with `enable`/`postWrite` when the write needs a follow-up step (e.g. partitioning).";
          apply = v: if builtins.isBool v then { enable = v; postWrite = ""; } else v;
        };

        nixosAnywhere = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to generate a nixos-anywhere deployment app for this host.";
        };

      };

    };
    }
  );

  hostsInClass = class: lib.filterAttrs (_: host: host.class == class) config.host;

  # Home Manager identity and shared module assembly.
  mkHomeModules =
    hostName: hostStateVersion: username: environment: featureModules:
    [
      (mkEnvironmentIdentityModule hostName hostStateVersion username environment)
      {
        home = {
          inherit username;
          inherit (environment) homeDirectory;
        };
      }
      backupExistingHomeFilesModule
    ]
    ++ featureModules
    ++ environment.modules;

  # Home Manager refuses to overwrite a pre-existing, unmanaged file (e.g.
  # mimeapps.list, written by some GUI app before Home Manager ever touched
  # it) unless `HOME_MANAGER_BACKUP_EXT` is set -- normally a per-invocation
  # CLI flag (`--backup-extension`) for standalone activations, or the
  # `home-manager.backupFileExtension` NixOS/nix-darwin option for
  # integrated ones, neither of which apply uniformly across this flake's
  # mix of integrated/standalone/Nix-on-Droid environments. Export the same
  # env var directly from an activation script instead, ordered before
  # `checkLinkTargets` (the collision check itself, which runs before
  # `writeBoundary`) so it's honored on every activation path without
  # per-file `force = true` or per-invocation flags. Also set
  # `HOME_MANAGER_BACKUP_OVERWRITE` so a stale `*.hm-backup` from a
  # previous activation is replaced rather than accumulating indefinitely
  # every time the same unmanaged file reappears in the way.
  backupExistingHomeFilesModule =
    { lib, ... }:
    {
      home.activation.backupExistingFiles = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        export HOME_MANAGER_BACKUP_EXT="hm-backup"
        export HOME_MANAGER_BACKUP_OVERWRITE="1"
      '';
    };

  mkEnvironmentIdentityModule =
    hostName: hostStateVersion: username: environment:
    { lib, ... }:
    {
      options.userEnvironment = {
        hostName = mkOption {
          type = types.nonEmptyStr;
          readOnly = true;
          description = "The host for which this user environment was built.";
        };

        hasGui = mkOption {
          type = types.bool;
          default = false;
          description = "Whether this environment has a graphical user-session context.";
        };

        username = mkOption {
          type = types.nonEmptyStr;
          readOnly = true;
          description = "The user for which this environment was built.";
        };

      };

      config = {
        userEnvironment = {
          inherit hostName username;
        };
        home.stateVersion = lib.mkDefault hostStateVersion;
      };
    };

  # NixOS host construction, including integrated Home Manager environments.
  integratedEnvironments = host: lib.filterAttrs (_: environment: environment.mode == "integrated") host.userEnvironment;

  mkIntegratedHomeManagerModule =
    hostName: host:
    let
      environments = integratedEnvironments host;
    in
    { config, lib, ... }:
    {
      imports = [ host.homeManager.flake.nixosModules.home-manager ];

      users.users = lib.mapAttrs (_: environment: {
        home = lib.mkDefault environment.homeDirectory;
      }) environments;

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        users = lib.mapAttrs (
          username: environment:
          {
            imports = mkHomeModules
              hostName
              host.stateVersion
              username
              environment
              config.userEnvironment.sharedModules;
          }
        ) environments;
      };
    };

  mkNixosConfiguration =
    hostName: host:
    let
      hasIntegratedEnvironments = integratedEnvironments host != { };
      hasStandaloneEnvironments = standaloneEnvironments host != { };
    in
    host.nixpkgs.lib.nixosSystem {
      modules = [
        inputs.self.modules.nixos.global-config
        inputs.self.modules.nixos.host-identity
      userEnvironmentModule
      ({ config, lib, ... }: {
        userEnvironment.sharedModules = lib.mkIf config.services.displayManager.enable [
          { userEnvironment.hasGui = true; }
        ];
      })
      {
          nixpkgs.hostPlatform = lib.mkDefault host.system;
          system.stateVersion = lib.mkDefault host.stateVersion;
          hostIdentity = {
            name = hostName;
            inherit (host) description primaryUser stateVersion;
          };
        }
      ]
      ++ lib.optional hasIntegratedEnvironments (mkIntegratedHomeManagerModule hostName host)
      ++ lib.optional hasStandaloneEnvironments {
        environment.systemPackages = [
          host.homeManager.flake.packages.${host.system}.home-manager
        ];
      }
      ++ host.modules;
    };

  nixosConfigurations = lib.mapAttrs mkNixosConfiguration (hostsInClass "nixos");

  # Nix-on-Droid host construction. Android exposes a single account, so a
  # droid host attaches at most one integrated environment; its home directory
  # and user name are platform facts that the registry mirrors rather than owns.
  mkNixOnDroidHomeManagerModule =
    hostName: host:
    let
      environments = integratedEnvironments host;
      usernames = builtins.attrNames environments;
    in
    { config, lib, ... }:
    {
      assertions = [
        {
          assertion = builtins.length usernames <= 1;
          message = "host ${hostName}: nix-on-droid supports a single user environment, but ${toString (builtins.length usernames)} are attached";
        }
      ];

      user.userName = lib.mkDefault (builtins.head usernames);

      home-manager = {
        useGlobalPkgs = true;
        config.imports = lib.concatLists (
          lib.mapAttrsToList (
            username: environment:
            mkHomeModules
              hostName
              host.stateVersion
              username
              environment
              config.userEnvironment.sharedModules
          ) environments
        );
      };
    };

  mkNixOnDroidConfiguration =
    hostName: host:
    let
      hasIntegratedEnvironments = integratedEnvironments host != { };
    in
    inputs.nix-on-droid.lib.nixOnDroidConfiguration {
      pkgs = import host.nixpkgs {
        inherit (host) system;
        overlays = [ inputs.nix-on-droid.overlays.default ];
      };

      inherit (host.nixOnDroid) bootstrapSystem;

      home-manager-path = host.homeManager.flake.outPath;

      modules = [
        inputs.self.modules.nixOnDroid.global-config
        inputs.self.modules.nixOnDroid.host-identity
        userEnvironmentModule
        {
          hostIdentity = {
            name = hostName;
            inherit (host) description primaryUser stateVersion;
          };
        }
      ]
      ++ lib.optional hasIntegratedEnvironments (mkNixOnDroidHomeManagerModule hostName host)
      ++ host.modules;
    };

  nixOnDroidConfigurations = lib.mapAttrs mkNixOnDroidConfiguration (hostsInClass "nixOnDroid");

  # Standalone Home Manager construction from the shared module assembly.
  standaloneEnvironments = host: lib.filterAttrs (_: environment: environment.mode == "standalone") host.userEnvironment;

  mkStandaloneHomeConfigurations =
    hostName: host:
    let
      nixosConfiguration = nixosConfigurations.${hostName};
    in
    lib.mapAttrs' (
      username: environment:
      lib.nameValuePair "${username}@${hostName}" (
        host.homeManager.flake.lib.homeManagerConfiguration {
          pkgs = nixosConfiguration.pkgs;
          modules = mkHomeModules
            hostName
            host.stateVersion
            username
            environment
            nixosConfiguration.config.userEnvironment.sharedModules;
        }
      )
    ) (standaloneEnvironments host);

  homeConfigurations = lib.mkMerge (
    lib.mapAttrsToList mkStandaloneHomeConfigurations (hostsInClass "nixos")
  );

  # Per-host ISO writer and nixos-anywhere helper apps.
  mkHostApps =
    hostName: host:
    let
      pkgs = host.nixpkgs.legacyPackages.${host.system};
      systemConfig = nixosConfigurations.${hostName}.config;
    in
    lib.mkMerge [

      (lib.mkIf host.capabilities.isoWriter.enable {
        ${host.system}."mkbootable-${hostName}" = {
          type = "app";
          meta.description = "Write the ${hostName} ISO to a block device: ${host.description}";
          program = toString (
            config.flake.lib.mkIsoWriter {
              name = hostName;
              inherit pkgs;
              iso = systemConfig.system.build.isoImage;
              postWrite = host.capabilities.isoWriter.postWrite;
            }
          );
        };
      })

      (lib.mkIf host.capabilities.nixosAnywhere {
        ${host.system}."deploy-${hostName}" =
          let
            deployer = config.flake.lib.mkNixosAnywhereDeployer {
              name = hostName;
              inherit pkgs;
              system-config = systemConfig;
            };
          in
          {
            type = "app";
            meta.description = "Deploy ${hostName} with nixos-anywhere: ${host.description}";
            program = "${deployer}/bin/deploy-${hostName}";
          };
      })

    ];
in
{

  /**
    Plumbs the `hosts` into the configuration output of their class and the
    associated `apps` (depending on enabled capabilities)
  */

  options = {
    host = mkOption {
      type = types.attrsOf hostType;
      default = { };
      description = "Declarative definitions of this flake's hosts.";
    };

    flake.nixOnDroidConfigurations = mkOption {
      type = types.lazyAttrsOf types.raw;
      default = { };
      description = "Nix-on-Droid configurations built from the host registry.";
    };

    flake.homeConfigurations = mkOption {
      type = types.lazyAttrsOf types.raw;
      default = { };
      description = "Standalone Home Manager configurations built from the host registry.";
    };

  };

  config = {
    flake.modules.nixos.user-environment = userEnvironmentModule;
    flake.modules.nixOnDroid.user-environment = userEnvironmentModule;
    flake.nixosConfigurations = nixosConfigurations;
    flake.nixOnDroidConfigurations = nixOnDroidConfigurations;
    flake.homeConfigurations = homeConfigurations;
    flake.apps = lib.mkMerge (lib.mapAttrsToList mkHostApps (hostsInClass "nixos"));
  };
}
