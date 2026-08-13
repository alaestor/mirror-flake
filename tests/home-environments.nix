{
  inputs,
  pkgs,
  system,
}:
let
  hostName = "home-environment-fixture";
  integratedOnlyHostName = "integrated-only-fixture";
  missingStateVersionHostName = "missing-state-version-fixture";
  stateVersion = "24.11";
  integratedUsername = "integrated-user";
  standaloneUsername = "standalone-user";
  serviceUsername = "fixture-service";

  attachedModule =
    { lib, pkgs, ... }:
    {
      options.test.attached = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
      };

      config = {
        test.attached = "explicit-module";
        home.packages = [ pkgs.hello ];
      };
    };

  featureModule =
    { config, lib, ... }:
    {
      options.test.feature = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
      };

      config.test.feature = "contributed-by-${config.userEnvironment.hostName}";
    };

  fixture = inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [ ../modules/host-plumbing/registry.nix ];

    host.${hostName} = {
      inherit system stateVersion;
      nixpkgs = inputs.unstable-nixpkgs;
      description = "Home environment registry test fixture.";
      primaryUser = integratedUsername;

      modules = [
        ({ lib, ... }: {
          userEnvironment.sharedModules = [ featureModule ];

          users = {
            groups.${serviceUsername} = { };
            users.${serviceUsername} = {
              isSystemUser = true;
              group = serviceUsername;
            };
          };
        })
      ];

      userEnvironment = {
        ${integratedUsername} = {
          mode = "integrated";
          modules = [ attachedModule ];
        };
        ${standaloneUsername} = {
          mode = "standalone";
          modules = [ attachedModule ];
        };
      };
    };

  };

  integratedOnlyFixture = inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [ ../modules/host-plumbing/registry.nix ];

    host.${integratedOnlyHostName} = {
      inherit system stateVersion;
      nixpkgs = inputs.unstable-nixpkgs;
      description = "Integrated-only Home environment registry test fixture.";
      primaryUser = integratedUsername;
      modules = [ ];
      userEnvironment.${integratedUsername} = {
        mode = "integrated";
        modules = [ attachedModule ];
      };
    };
  };

  missingStateVersionFixture = inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [ ../modules/host-plumbing/registry.nix ];

    host.${missingStateVersionHostName} = {
      inherit system;
      nixpkgs = inputs.unstable-nixpkgs;
      description = "Fixture that must reject an omitted host state version.";
      primaryUser = integratedUsername;
      modules = [ ];
    };
  };

  nixosConfig = fixture.nixosConfigurations.${hostName}.config;
  integrated = nixosConfig.home-manager.users.${integratedUsername};
  standalone = fixture.homeConfigurations."${standaloneUsername}@${hostName}".config;
  integratedOnlyPackages =
    integratedOnlyFixture.nixosConfigurations.${integratedOnlyHostName}.config.environment.systemPackages;
  missingStateVersion = builtins.tryEval (
    missingStateVersionFixture.nixosConfigurations.${missingStateVersionHostName}.config.hostIdentity.stateVersion
  );

  expectedFeature = "contributed-by-${hostName}";
  homeManagerPackage = inputs.unstable-home-manager.packages.${system}.home-manager;
  helloDrvPath = config: (builtins.head config.home.packages).drvPath;
  hasPackage = package: packages: builtins.any (candidate: candidate.drvPath == package.drvPath) packages;

  assertions = [
    {
      assertion = !missingStateVersion.success;
      message = "host declarations may not omit stateVersion";
    }
    {
      assertion = integrated.userEnvironment == {
        inherit hostName;
        hasGui = false;
        username = integratedUsername;
      };
      message = "integrated identity differs from its host attachment";
    }
    {
      assertion = standalone.userEnvironment == {
        inherit hostName;
        hasGui = false;
        username = standaloneUsername;
      };
      message = "standalone identity differs from its host attachment";
    }
    {
      assertion = integrated.test.feature == expectedFeature;
      message = "integrated environment missed its host feature contribution";
    }
    {
      assertion = standalone.test.feature == expectedFeature;
      message = "standalone environment missed its host feature contribution";
    }
    {
      assertion = integrated.test.attached == standalone.test.attached;
      message = "activation modes evaluated the explicit module differently";
    }
    {
      assertion = integrated.home.stateVersion == stateVersion;
      message = "integrated environment did not inherit the host state version";
    }
    {
      assertion = standalone.home.stateVersion == stateVersion;
      message = "standalone environment did not inherit the host state version";
    }
    {
      assertion = integrated.home.homeDirectory == "/home/${integratedUsername}";
      message = "integrated environment did not receive its default home directory";
    }
    {
      assertion = standalone.home.homeDirectory == "/home/${standaloneUsername}";
      message = "standalone environment did not receive its default home directory";
    }
    {
      assertion = helloDrvPath integrated == helloDrvPath standalone;
      message = "activation modes did not use the same host package set";
    }
    {
      assertion = !(builtins.hasAttr serviceUsername nixosConfig.home-manager.users);
      message = "host feature contributions leaked into an unmanaged service account";
    }
    {
      assertion = builtins.hasAttr "${standaloneUsername}@${hostName}" fixture.homeConfigurations;
      message = "standalone attachment did not produce a homeConfigurations output";
    }
    {
      assertion = !(builtins.hasAttr "${integratedUsername}@${hostName}" fixture.homeConfigurations);
      message = "integrated attachment unexpectedly produced a standalone output";
    }
    {
      assertion = hasPackage homeManagerPackage nixosConfig.environment.systemPackages;
      message = "standalone attachment did not install its selected Home Manager CLI";
    }
    {
      assertion = !(hasPackage homeManagerPackage integratedOnlyPackages);
      message = "Home Manager CLI was installed without a standalone attachment";
    }
  ];

  failures = map (result: result.message) (
    builtins.filter (result: !result.assertion) assertions
  );
in
pkgs.runCommand "home-environments-test"
  {
    passAsFile = [ "failureReport" ];
    failureReport = builtins.concatStringsSep "\n" failures;
  }
  ''
    if [[ -s "$failureReportPath" ]]; then
      echo "Home environment registry assertions failed:" >&2
      sed 's/^/- /' "$failureReportPath" >&2
      exit 1
    fi
    touch "$out"
  ''
