/**

Declarative registry for NixOS hosts in this flake.
Each host is defined as an attribute in `config.host` and automatically
produces:
 - A NixOS configuration under `flake.nixosConfigurations`
 - Optional helper apps (ISO writer, nixos-anywhere deployer)

The generated NixOS configurations are pre-composed with
`global-config` and `host-identity` modules so that every host
inherits common base settings and a consistent identity.

Hosts may also attach Home Manager environments under `userEnvironment`.
Feature-contributed and explicitly attached modules are composed identically for
integrated and standalone activation.

*/
{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;

  userEnvironmentModule =
    { lib, ... }:
    {
      options.userEnvironment.sharedModules = lib.mkOption {
        type = lib.types.listOf lib.types.deferredModule;
        default = [ ];
        description = "Home Manager modules contributed by this host's NixOS features.";
      };
    };

  userEnvironmentType = types.submodule (
    { name, ... }:
    {
      options = {
        mode = mkOption {
          type = types.enum [
            "integrated"
            "standalone"
          ];
          description = "Whether this user environment is activated with NixOS or independently.";
        };

        homeDirectory = mkOption {
          type = types.nonEmptyStr;
          default = if name == "root" then "/root" else "/home/${name}";
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
  hostType = types.submodule {
    options = {

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
        default = "26.05";
        description = "The NixOS state version, also used as the default Home Manager state version.";
      };

      modules = mkOption {
        type = types.listOf types.deferredModule;
        default = [ ];
        description = "The NixOS modules which define this host.";
      };

      homeManager.channel = mkOption {
        type = types.enum [
          "stable"
          "unstable"
        ];
        default = "unstable";
        description = "The Home Manager input used for this host's user environments.";
      };

      userEnvironment = mkOption {
        type = types.attrsOf userEnvironmentType;
        default = { };
        description = "User environments deployed to this host.";
      };

      /**
        Set host configuration capabilities such as enabling the `nix run`
        `deploy` nixosAnywhere scripts, or `mkBootable` ISO scripts.
      */
      capabilities = {

        isoWriter = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to generate a standard ISO writer app for this host.";
        };

        nixosAnywhere = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to generate a nixos-anywhere deployment app for this host.";
        };

      };

    };
  };

  selectHomeManager =
    host:
    if host.homeManager.channel == "stable" then
      inputs.stable-home-manager
    else
      inputs.unstable-home-manager;

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
    ]
    ++ featureModules
    ++ environment.modules;

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

  integratedEnvironments = host: lib.filterAttrs (_: environment: environment.mode == "integrated") host.userEnvironment;

  mkIntegratedHomeManagerModule =
    hostName: host:
    let
      environments = integratedEnvironments host;
      homeManager = selectHomeManager host;
    in
    { config, lib, ... }:
    {
      imports = [ homeManager.nixosModules.home-manager ];

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
    name: host:
    let
      hasIntegratedEnvironments = integratedEnvironments host != { };
    in
    host.nixpkgs.lib.nixosSystem {
      modules = [
        inputs.self.modules.nixos.global-config
        inputs.self.modules.nixos.host-identity
        userEnvironmentModule
        {
          nixpkgs.hostPlatform = lib.mkDefault host.system;
          system.stateVersion = lib.mkDefault host.stateVersion;
          hostIdentity = {
            inherit name;
            inherit (host) description primaryUser stateVersion;
          };
        }
      ]
      ++ lib.optional hasIntegratedEnvironments (mkIntegratedHomeManagerModule name host)
      ++ host.modules;
    };

  configurations = lib.mapAttrs mkNixosConfiguration config.host;

  standaloneEnvironments = host: lib.filterAttrs (_: environment: environment.mode == "standalone") host.userEnvironment;

  mkStandaloneHomeConfigurations =
    hostName: host:
    let
      homeManager = selectHomeManager host;
      nixosConfiguration = configurations.${hostName};
    in
    lib.mapAttrs' (
      username: environment:
      lib.nameValuePair "${username}@${hostName}" (
        homeManager.lib.homeManagerConfiguration {
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
    lib.mapAttrsToList mkStandaloneHomeConfigurations config.host
  );

  mkHostApps =
    name: host:
    let
      pkgs = host.nixpkgs.legacyPackages.${host.system};
      systemConfig = configurations.${name}.config;
    in
    lib.mkMerge [

      (lib.mkIf host.capabilities.isoWriter {
        ${host.system}."mkbootable-${name}" = {
          type = "app";
          meta.description = "Write the ${name} ISO to a block device: ${host.description}";
          program = toString (
            config.flake.lib.mkIsoWriter {
              inherit name pkgs;
              iso = systemConfig.system.build.isoImage;
            }
          );
        };
      })

      (lib.mkIf host.capabilities.nixosAnywhere {
        ${host.system}."deploy-${name}" =
          let
            deployer = config.flake.lib.mkNixosAnywhereDeployer {
              inherit name pkgs;
              system-config = systemConfig;
            };
          in
          {
            type = "app";
            meta.description = "Deploy ${name} with nixos-anywhere: ${host.description}";
            program = "${deployer}/bin/deploy-${name}";
          };
      })

    ];
in
{

  /**
    Plumbs the `hosts` into `nixosConfiguration` and associated `apps`
    (depending on enabled capabilities)
  */

  options = {
    host = mkOption {
      type = types.attrsOf hostType;
      default = { };
      description = "Declarative definitions of this flake's NixOS hosts.";
    };

  };

  config = {
    flake.modules.nixos.user-environment = userEnvironmentModule;
    flake.nixosConfigurations = configurations;
    flake.homeConfigurations = homeConfigurations;
    flake.apps = lib.mkMerge (lib.mapAttrsToList mkHostApps config.host);
  };
}
