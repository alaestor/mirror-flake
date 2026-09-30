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

      preprompt = agents.fragments.shell pkgs + "\n" + agents.fragments.rtk + "\n" + agents.fragments.memory;

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
        guard) context_guard=true ;;
        mem|memory) memory_enabled=true ;;
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
            # The NixOS-managed hook is stable. Resolve its implementation
            # from this Home Manager generation in both native and VM sessions.
            export AGENT_DIRECTIVES_BIN=${lib.getExe (agents.directives pkgs)}

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
              # The guest volume persists across generations. Remove only
              # links created by the old skill registration; leave user skills.
              for skill_name in \
                general-testing git-conventional-commits \
                git-howto-change-commit-message-history mp-domain-modeling \
                mp-grill-me mp-grill-with-docs mp-grilling mp-wait-what \
                nix-flake-component-flake-file nix-flake-component-flake-parts \
                nix-flake-component-import-tree nix-flake-pattern-dendritic-flakes \
                nix-flake-pattern-normal-flakes procedure-handoff procedure-pickup \
                prose-docs prose-unslop speaking subagents-local-sequential \
                subagents-manual
              do
                skill_link="$HOME/.codex/skills/$skill_name"
                [[ -L "$skill_link" ]] || continue
                skill_target="$(${pkgs.coreutils}/bin/readlink -- "$skill_link")"
                [[ "$skill_target" == /nix/store/*/data/agents/skills/* ]] || continue
                ${pkgs.coreutils}/bin/rm -- "$skill_link"
              done
              ${lib.concatMapStringsSep "\n" (skillName: ''
                skill_link="$HOME/.codex/skills/${skillName}"
                if [[ ! -e "$skill_link" && ! -L "$skill_link" ]]; then
                  ${pkgs.coreutils}/bin/ln -s ${lib.escapeShellArg agents.skills.${skillName}} "$skill_link"
                fi
              '') (builtins.attrNames agents.skills)}
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
            context_guard=false
            memory_enabled=false

            ${agents.mkSelectorLoop {
              caseArms = codexCaseArms;
              helpFlag = "--cx-help";
              helpLines = [
                "usage: ${name} [luna|terra|sol|astra] [lo|med|hi|xhi] [full|small] [user|auto|bypass] [guard|mem|memory] [--] [codex arguments...]"
                "mem/memory enables shared project and global Cognee memory; the local LLM must be available"
                "guard opts into context handoffs and compaction blocking; normal compaction is the default"
              ];
              argsVar = "passthrough";
            }}

            codex_args=()
            # CLI dotted paths do not parse quoted keys. Pass an inline table
            # so dots in config.toml remain part of each handler's identity.
            guard_state=${
              lib.escapeShellArg (
                "hooks.state={"
                + lib.concatMapStringsSep ", " (
                  key: "${builtins.toJSON key}={enabled=GUARD_ENABLED}"
                ) agents.codexGuardHookKeys
                + "}"
              )
            }
            codex_args+=( -c "''${guard_state//GUARD_ENABLED/$context_guard}" )
            ${mkOverrideArgs baseOverrides}
            project_memories="$(${lib.getExe (agents.projectMemory pkgs)} list)"
            session_instructions=${lib.escapeShellArg resolvedPrompts.plain.preamble}
            [[ -z "$project_memories" ]] || session_instructions+=$'\n\n# Available project memories\n'"$project_memories"
            memory_mcp=${lib.escapeShellArg ("mcp_servers.cognee={command=${builtins.toJSON (lib.getExe config.services.cognee-memory.mcpBridge)},enabled=MEMORY_ENABLED}")}
            codex_args+=( -c "''${memory_mcp//MEMORY_ENABLED/$memory_enabled}" )
            if [[ "$memory_enabled" == true ]]; then
              ${
                if config.services.cognee-memory.enable then
                  ''
                    ${lib.getExe config.services.cognee-memory.sessionPrepare}
                  ''
                else
                  ''
                    echo 'cognee: memory is disabled in this configuration' >&2
                    exit 1
                  ''
              }
              COGNEE_MEMORY_PROJECT="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")"
              export COGNEE_MEMORY_PROJECT
              session_instructions+=$'\n'${lib.escapeShellArg agents.cogneeInstructions}
            fi
            codex_args+=( -c "developer_instructions=$(jq -Rn --arg text "$session_instructions" '$text')" )

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
              beforeExec = agents.cogneeSandboxText pkgs config;
              sessionArgsVar = "session_args";
              sessionEnvironmentVar = "session_environment";
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
      codexConfigFile = (pkgs.formats.toml { }).generate "codex-config" config.programs.codex.settings;
      codexContextFile = pkgs.writeText "codex-AGENTS.md" config.programs.codex.context;
    in
    {
      imports = [
        inputs.self.modules.homeManager.tokview
        inputs.self.modules.homeManager.agents-prompt-preview
        inputs.self.modules.homeManager.cognee-memory
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
        services.cognee-memory.enable = lib.mkDefault true;
        home.packages =
          let
            cxWrappers = mkCodexWrapper "cx";
          in
          [
            cxWrappers.native
            cxWrappers.wrapped
            (agents.directives pkgs)
          ];
        agents.promptPreview.codex = resolvedPrompts;

        programs.codex = {
          enable = lib.mkDefault true;
          context = resolvedPrompts.plain.context;
          skills = agents.skills;
          rules.default = self.data.path "programs/codex/default.rules";
          settings = lib.mkMerge [
            defaultSettings
            {
              hooks.state = builtins.listToAttrs (
                map (key: {
                  name = key;
                  value.enabled = false;
                }) agents.codexGuardHookKeys
              );
            }
            (lib.optionalAttrs (cfg.modelInstructionsFile != null) {
              model_instructions_file = lib.mkDefault cfg.modelInstructionsFile;
            })
          ];
        };
      };
    };
}
