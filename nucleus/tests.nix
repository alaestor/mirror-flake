{ lib }:
let
  listModules = import ./list-modules.nix;
  render = import ./render.nix { inherit lib; };

  discovered = map (path: lib.removePrefix "${toString ./tests/fixture}/" (toString path)) (
    listModules ./tests/fixture
  );

  rendered = render {
    description = "Fixture flake";
    outputsExpression = "inputs: { inherited = inputs.token; }";
    inputs = {
      flake-parts = {
        url = "github:hercules-ci/flake-parts";
        flake = null;
        follows = null;
        inputs.nixpkgs-lib = {
          follows = "nixpkgs";
          inputs = { };
        };
      };
      nixpkgs = {
        url = "nixpkgs/nixos-unstable";
        flake = null;
        follows = null;
        inputs = { };
      };
    };
  };
  renderedValue = import (builtins.toFile "nucleus-render-fixture.nix" rendered);

  flakePartsTestHarness = {
    options.perSystem = lib.mkOption {
      type = lib.types.deferredModule;
    };
  };

  evaluatedModules = lib.evalModules {
    specialArgs.inputs = { };
    modules = [
      flakePartsTestHarness
      ./flake-module.nix
      {
        flake.modules.nixos.example = {
          options.first = lib.mkOption {
            type = lib.types.bool;
          };
          config.first = true;
        };
      }
      {
        flake.modules.homeManager.example = { };
        flake.modules.nixos.example = {
          options.second = lib.mkOption {
            type = lib.types.bool;
          };
          config.second = true;
        };
      }
    ];
  };

  composedModule = lib.evalModules {
    modules = [ evaluatedModules.config.flake.modules.nixos.example ];
  };

  invalidModule = builtins.tryEval (
    (lib.evalModules {
      specialArgs.inputs = { };
      modules = [
        flakePartsTestHarness
        ./flake-module.nix
        { flake.modules.nixos.example = 42; }
      ];
    }).config.flake.modules.nixos.example
  );
in
assert discovered == [
  "a.nix"
  "nested/b.nix"
];
assert renderedValue.description == "Fixture flake";
assert renderedValue.inputs == {
  flake-parts = {
    url = "github:hercules-ci/flake-parts";
    inputs.nixpkgs-lib.follows = "nixpkgs";
  };
  nixpkgs.url = "nixpkgs/nixos-unstable";
};
assert (renderedValue.outputs { token = "passed-through"; }).inherited == "passed-through";
assert builtins.attrNames evaluatedModules.config.flake.modules == [
  "homeManager"
  "nixos"
];
assert builtins.attrNames evaluatedModules.config.flake.modules.nixos == [ "example" ];
assert builtins.attrNames evaluatedModules.config.flake.modules.homeManager == [ "example" ];
assert composedModule.config == {
  first = true;
  second = true;
};
assert !invalidModule.success;
assert builtins.deepSeq (import ./tests-inputs.nix { inherit lib; }) true;
{
  inherit discovered rendered;
}
