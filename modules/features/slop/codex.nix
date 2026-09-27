/**
  Codex CLI with shared agent tools, prompts, and model selectors.
*/
{ inputs, self, ... }:
{
  flake.modules.homeManager.codex =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      agents = self.lib.agents;
      cfg = config.codex;
      codexPackage = config.programs.codex.package;

      instructionFiles = {
        small = self.data.path "programs/codex/codex-instructions-gpt-5-small.md";
      };

      cliBase = with pkgs; [
        rtk
        tlrc
      ];

      cliTools = agents.tools pkgs;

      preprompt = agents.fragments.shell pkgs + "\n" + agents.fragments.rtk;

      promptLayers = {
        common = {
          preamble.add = [ preprompt ];
          context.replace = [ agents.context ];
        };
      };
      mkResolvedPrompt =
        variant:
        agents.mkPrompt {
          model = "default";
          inherit variant;
          layers = promptLayers;
        };
      resolvedPrompts = {
        plain = mkResolvedPrompt "plain";
      };
      baseOverrides = [
        "developer_instructions=${builtins.toJSON resolvedPrompts.plain.preamble}"
      ]
      ++ lib.optional config.services.tokview.enable "openai_base_url=${builtins.toJSON "http://127.0.0.1:${toString config.services.tokview.proxyPort}/v1"}";
      mkOverrideArgs =
        values:
        lib.concatMapStringsSep "\n" (value: ''
          # shellcheck disable=SC2016 # Config values are intentionally literal.
          codex_args+=( -c ${lib.escapeShellArg value} )
        '') values;

      # Case arms handed to `agents.mkSelectorLoop`; `--cx-help`/`--`/catch-all
      # are the loop's own job, not the harness's — see selector-loop.nix.
      codexCaseArms = ''
        luna) model="gpt-6-luna" ;;
        terra) model="gpt-6-terra" ;;
        sol) model="gpt-6-sol" ;;
        astra) model="gpt-6-astra" ;;
        lo|low) effort="low" ;;
        med|medium) effort="medium" ;;
        hi|high) effort="high" ;;
        xhi|xhigh) effort="xhigh" ;;
        full) instruction_file="" ;;
        small) instruction_file=${lib.escapeShellArg (toString instructionFiles.small)} ;;
        user) reviewer="user"; approval_policy="untrusted"; sandbox_mode="workspace-write" ;;
        auto) reviewer="auto_review" ;;
        bypass|yolo) approval_policy="never"; sandbox_mode="danger-full-access" ;;
      '';

      mkCodexWrapper =
        name:
        agents.mkHarnessWrappers pkgs {
          inherit name;
          runtimeInputs = cliBase ++ cliTools;
          nativeText = ''
            # Harmless if Codex never exports its own `find` shell function
            # the way Claude does — the guard then just wraps plain
            # findutils. See `findGuardBashEnv`'s doc comment (`libagents.nix`).
            export BASH_ENV=${agents.findGuardBashEnv pkgs}

            # Without this the guest has no git identity at all and `git
            # commit` fails; see `gitEnvironmentText` (`libagents.nix`).
            ${agents.gitEnvironmentText config}

            # The sandbox keeps Codex's SQLite state on a persistent local
            # volume. Recreate only the Home Manager-owned links there.
            if [[ "''${AGENT_VM_GUEST:-}" == 1 ]]; then
              ${pkgs.coreutils}/bin/mkdir -p "$HOME/.codex/rules" "$HOME/.codex/skills"
              ${pkgs.coreutils}/bin/ln -sfn ${lib.escapeShellArg codexConfigFile} "$HOME/.codex/config.toml"
              ${pkgs.coreutils}/bin/ln -sfn ${lib.escapeShellArg codexContextFile} "$HOME/.codex/AGENTS.md"
              ${pkgs.coreutils}/bin/ln -sfn ${lib.escapeShellArg (self.data.path "programs/codex/default.rules")} "$HOME/.codex/rules/default.rules"
              ${lib.concatMapStringsSep "\n" (skillName: ''
                ${pkgs.coreutils}/bin/ln -sfn ${
                  lib.escapeShellArg (toString codexSkills.${skillName})
                } "$HOME/.codex/skills/${skillName}"
              '') (builtins.attrNames codexSkills)}
            fi

            model=""
            effort=""
            instruction_file=${
              lib.escapeShellArg (
                if cfg.modelInstructionsFile == null then "" else toString cfg.modelInstructionsFile
              )
            }
            reviewer="auto_review"
            approval_policy="never"
            sandbox_mode="danger-full-access"
            passthrough=()

            ${agents.mkSelectorLoop {
              caseArms = codexCaseArms;
              helpFlag = "--cx-help";
              helpLines = [
                "usage: ${name} [luna|terra|sol|astra] [lo|med|hi|xhi] [full|small] [user|auto|bypass] [--] [codex arguments...]"
              ];
              argsVar = "passthrough";
            }}

            codex_args=()
            ${mkOverrideArgs baseOverrides}

            if [[ -n "$model" ]]; then
              codex_args+=( --model "$model" )
            fi
            if [[ -n "$effort" ]]; then
              codex_args+=( -c "model_reasoning_effort=\"''${effort}\"" )
            fi
            if [[ -n "$instruction_file" ]]; then
              codex_args+=( -c "model_instructions_file=\"''${instruction_file}\"" )
            fi
            if [[ -n "$reviewer" ]]; then
              codex_args+=( -c "approvals_reviewer=\"''${reviewer}\"" )
            fi
            if [[ -n "$approval_policy" ]]; then
              codex_args+=( -c "approval_policy=\"''${approval_policy}\"" )
            fi
            if [[ -n "$sandbox_mode" ]]; then
              codex_args+=( -c "sandbox_mode=\"''${sandbox_mode}\"" )
            fi

            # automatically trust the working-directory
            codex_args+=( -c "projects={\"$PWD\"={trust_level=\"trusted\"}}")

            exec ${lib.optionalString config.services.tokview.enable "${lib.getExe config.services.tokview.sessionLauncher} "}${lib.getExe codexPackage} "''${codex_args[@]}" "''${passthrough[@]}"
          '';

          sandbox =
            native:
            agents.mkVmSandbox pkgs {
              inherit name native;
              helpFlag = "--cx-help";
              herdrAgent = "codex";
            };
        };

      normalizeSettingsValue =
        value:
        if builtins.isString value then
          builtins.replaceStrings [ "/home/user" ] [ config.home.homeDirectory ] value
        else if builtins.isList value then
          map normalizeSettingsValue value
        else if builtins.isAttrs value then
          lib.mapAttrs' (
            name: nestedValue:
            lib.nameValuePair (builtins.replaceStrings [ "/home/user" ] [ config.home.homeDirectory ] name) (
              normalizeSettingsValue nestedValue
            )
          ) value
        else
          value;
      referenceSettings = builtins.removeAttrs (normalizeSettingsValue (
        builtins.fromTOML (self.data.read "programs/codex/config.toml")
      )) [ "model_instructions_file" ];
      defaultSettings = lib.mapAttrsRecursive (_: lib.mkDefault) referenceSettings;
      skillsRoot = self.data.path "agents/skills";
      codexConfigFile = (pkgs.formats.toml { }).generate "codex-config" config.programs.codex.settings;
      codexContextFile = pkgs.writeText "codex-AGENTS.md" config.programs.codex.context;
      codexSkills = agents.collectSkills skillsRoot;
    in
    {
      imports = [
        inputs.self.modules.homeManager.tokview
        inputs.self.modules.homeManager.agents-prompt-preview
      ];

      # Calling `codex features list` shows current feature flags.
      # Feature defaults: https://github.com/openai/codex/blob/rust-v0.145.0/codex-rs/features/src/lib.rs
      # Configuration types: https://github.com/openai/codex/blob/rust-v0.145.0/codex-rs/config/src/config_toml.rs
      options.codex.modelInstructionsFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = instructionFiles.small;
        defaultText = lib.literalExpression "the bundled small instruction file";
        description = "Default model instruction file used by Codex and cx; null leaves it unset.";
      };

      config = {
        services.tokview.enable = lib.mkDefault true;
        home.packages =
          let
            cxWrappers = mkCodexWrapper "cx";
          in
          [
            cxWrappers.native
            cxWrappers.wrapped
          ];
        agents.promptPreview.codex = resolvedPrompts;

        programs.codex = {
          enable = lib.mkDefault true;
          context = resolvedPrompts.plain.context;
          rules.default = self.data.path "programs/codex/default.rules";
          skills = agents.collectSkills skillsRoot;
          settings = lib.mkMerge [
            defaultSettings
            (lib.optionalAttrs (cfg.modelInstructionsFile != null) {
              model_instructions_file = lib.mkDefault cfg.modelInstructionsFile;
            })
          ];
        };
      };
    };
}
