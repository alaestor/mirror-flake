{
  config,
  inputs,
  lib,
  ...
}:
let
  cfg = config.nucleus;

  followsOption = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "Another flake input path to follow.";
  };

  inputOverridesType = lib.types.lazyAttrsOf (
    lib.types.submodule {
      options = {
        follows = followsOption;
        inputs = lib.mkOption {
          type = inputOverridesType;
          default = { };
          description = "Nested input overrides.";
        };
      };
    }
  );

  inputType = lib.types.submodule {
    options = {
      url = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Flake reference URL.";
      };

      flake = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Whether the input is a flake.";
      };

      follows = followsOption;

      inputs = lib.mkOption {
        type = inputOverridesType;
        default = { };
        description = "Overrides for the input's own inputs.";
      };
    };
  };

  rendered =
    assert lib.assertMsg (invalidFollows == [ ]) ''
      nucleus.inputs: the following `follows` targets don't name a declared
      top-level nucleus input, so `nix flake lock` will fail for them later
      instead of failing here at declaration time:
      ${lib.concatMapStringsSep "\n" (e: "  ${e.prefix}.follows = \"${e.follows}\"") invalidFollows}
    '';
    import ./render.nix { inherit lib; } {
      inherit (cfg) description inputs outputsExpression;
    };

  tests = import ./tests.nix { inherit lib; };

  # A `follows` typo (e.g. "nipxkgs") otherwise renders happily and only
  # fails much later inside `nix flake lock`, from write-flake's captured
  # log rather than at the point of declaration. Validate that every
  # `follows` value's root segment names a declared top-level input.
  declaredInputNames = builtins.attrNames cfg.inputs;

  collectFollows =
    prefix: value:
    lib.optional (value.follows != null) {
      inherit prefix;
      inherit (value) follows;
    }
    ++ lib.concatLists (
      lib.mapAttrsToList (name: collectFollows "${prefix}.inputs.${name}") value.inputs
    );

  allFollows = lib.concatLists (
    lib.mapAttrsToList (name: collectFollows "nucleus.inputs.${name}") cfg.inputs
  );

  # `follows = ""` is a deliberate idiom to unset an inherited default
  # follow (see e.g. standard-disk.nix's impermanence input), not a typo.
  invalidFollows = builtins.filter (
    entry:
    entry.follows != ""
    && !builtins.elem (lib.head (lib.splitString "/" entry.follows)) declaredInputNames
  ) allFollows;
in
{
  options.flake.modules = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.lazyAttrsOf lib.types.deferredModule);
    default = { };
    description = "Named modules exported by module class.";
  };

  options.nucleus = {
    enable = lib.mkEnableOption "the local flake source generator";

    description = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Description written to flake.nix.";
    };

    inputs = lib.mkOption {
      type = lib.types.lazyAttrsOf inputType;
      default = { };
      description = "Flake inputs collected from flake-parts modules.";
    };

    outputsExpression = lib.mkOption {
      type = lib.types.lines;
      default = ''
        inputs:
          inputs.flake-parts.lib.mkFlake { inherit inputs; } {
            imports = [ ./nucleus/flake-module.nix ]
              ++ import ./nucleus/list-modules.nix ./modules;
          }
      '';
      description = "Nix expression used as the flake outputs function.";
    };
  };

  config = lib.mkIf cfg.enable {
    perSystem =
      { pkgs, ... }:
      let
        generated = pkgs.writeText "flake.nix" rendered;
        writeFlake = pkgs.writeShellApplication {
          name = "write-flake";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.diffutils
            pkgs.nix
          ];
          text = ''
            export NUCLEUS_GENERATED=${lib.escapeShellArg (toString generated)}
            export NUCLEUS_NIX=${lib.escapeShellArg (lib.getExe pkgs.nix)}
            export NUCLEUS_NIX_INSTANTIATE=${
              lib.escapeShellArg (lib.getExe' pkgs.nix "nix-instantiate")
            }
            exec ${lib.getExe pkgs.bash} ${./write-flake.sh} "$@"
          '';
        };
      in
      {
        apps.write-flake = {
          type = "app";
          program = lib.getExe writeFlake;
          meta.description = "Regenerate flake.nix using nucleus.";
        };

        checks.nucleus = builtins.deepSeq tests (
          pkgs.runCommandLocal "check-nucleus" { } ''
            diff -u ${inputs.self}/flake.nix ${generated}
            touch $out
          ''
        );

        packages.nucleus = generated;
      };
  };
}
