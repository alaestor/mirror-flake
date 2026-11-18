{ inputs, pkgs, system }:
let
  lib = inputs.nixpkgs.lib;
  hostName = "android-fixture";
  username = "fixture-user";
  homeDirectory = "/data/data/com.termux.nix/files/home";
  stateVersion = "24.05";

  # Observe forwarding while still evaluating the real Android builder.
  fixtureInputs = inputs // {
    nix-on-droid = inputs.nix-on-droid // {
      lib = inputs.nix-on-droid.lib // {
        nixOnDroidConfiguration = args:
          (inputs.nix-on-droid.lib.nixOnDroidConfiguration args) // {
            testBuilderArguments = {
              inherit (args) bootstrapSystem home-manager-path;
            };
          };
      };
    };
  };
  attached = { lib, ... }: {
    options.test.attached = lib.mkOption { type = lib.types.str; };
    config.test.attached = "explicit-module";
  };
  feature = { config, lib, ... }: {
    options.test.feature = lib.mkOption { type = lib.types.str; };
    config.test.feature = "feature-for-${config.userEnvironment.hostName}";
  };
  environment = { mode = "integrated"; modules = [ attached ]; };
  fixture = overrides: inputs.flake-parts.lib.mkFlake { inputs = fixtureInputs; } {
    imports = [ "${inputs.self}/modules/host-plumbing/registry.nix" ];
    host.${hostName} = {
      class = "nixOnDroid";
      system = "aarch64-linux";
      nixpkgs = inputs.android-nixpkgs;
      homeManager.flake = inputs.android-home-manager;
      nixOnDroid.bootstrapSystem = system;
      inherit stateVersion;
      description = "Android registry fixture";
      primaryUser = username;
      modules = [ {
        user.uid = 10000;
        user.gid = 10000;
        userEnvironment.sharedModules = [ feature ];
      } ];
      userEnvironment.${username} = environment;
    } // overrides;
  };
  integrated = fixture { };
  android = integrated.nixOnDroidConfigurations.${hostName};
  home = android.config.home-manager.config;
  unattached = (fixture { userEnvironment = { }; }).nixOnDroidConfigurations.${hostName};
  multiple = fixture {
    userEnvironment = { first = environment; second = environment; };
  };
  standalone = fixture {
    userEnvironment.${username} = environment // { mode = "standalone"; };
  };
  wrongHome = fixture {
    userEnvironment.${username} = environment // { homeDirectory = "/tmp/not-android-home"; };
  };
  rejected = result: !(builtins.tryEval result).success;
  # Force the platform assertion list, not merely the outer output attrset.
  acceptsAssertions = result: builtins.all (entry: entry.assertion)
    result.nixOnDroidConfigurations.${hostName}.config.assertions;
  checks = {
    outputClass = builtins.attrNames integrated.nixOnDroidConfigurations == [ hostName ]
      && (integrated.nixosConfigurations or { }) == { }
      && (integrated.homeConfigurations or { }) == { };
    identity = android.config.hostIdentity == {
      name = hostName;
      description = "Android registry fixture";
      primaryUser = username;
      inherit stateVersion;
    };
    platformIdentity = android.config.system.stateVersion == stateVersion
      && android.config.environment.sessionVariables.HOSTNAME == hostName
      && android.config.user.userName == username
      && android.config.user.home == homeDirectory;
    homeIdentity = home.home.username == username && home.home.homeDirectory == homeDirectory
      && home.home.stateVersion == stateVersion
      && home.userEnvironment.hostName == hostName
      && home.userEnvironment.username == username;
    sharedAndAttachedModules = home.test.feature == "feature-for-${hostName}"
      && home.test.attached == "explicit-module";
    homeManagerInput = android.testBuilderArguments.home-manager-path == inputs.android-home-manager.outPath;
    bootstrapSystem = android.testBuilderArguments.bootstrapSystem == system;
    noAttachment = unattached.config.home-manager.config == null
      && unattached.config.hostIdentity.name == hostName;
    multipleRejected = rejected (acceptsAssertions multiple);
    standaloneRejected = rejected (acceptsAssertions standalone);
    homeOverrideRejected = rejected (
      wrongHome.nixOnDroidConfigurations.${hostName}.config.home-manager.config.home.homeDirectory
    );
    validAssertions = acceptsAssertions integrated;
  };
  failures = lib.attrNames (lib.filterAttrs (_: passed: !passed) checks);
in
assert lib.assertMsg (failures == [ ]) "Android registry contracts failed: ${lib.concatStringsSep ", " failures}";
pkgs.runCommand "droid-registry-test" { } ''touch "$out"''
