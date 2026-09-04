/**
  Codex CLI wired through the Headroom proxy, with model-specific
  instruction files.
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
      proxy = config.services.headroom-proxy;
      codexPackage = config.programs.codex.package;
      headroomPackage = proxy.package;
      sandboxWritableRoots = agents.sandboxWritableRootsFor "$HOME";

      instructionFiles = {
        small = self.data.path "programs/codex/codex-instructions-gpt-5-small.md";
      };

      cliBase = with pkgs; [
        rtk
        tlrc
      ];

      cliTools = agents.tools pkgs;

      # Codex previously ran its own, slightly drifted RTK prose and lacked
      # the headroom-shaping paragraph entirely; both now come from the
      # shared fragments verbatim (claude-code.nix's wording), which is the
      # one intentional behaviour change in this move — see the implementation
      # guide, Phase 1.
      preprompt = agents.fragments.shell pkgs + "\n" + agents.fragments.headroom + "\n" + agents.fragments.rtk;

      serena = inputs.alpkgs.packages.${pkgs.stdenv.hostPlatform.system}.serena;

      serenaInstructions = agents.fragments.serena;

      # `variant` is "plain" or "serena", matching `withSerena` in
      # `mkCodexWrapper` below. Codex has no `system` depth of its own here —
      # `model_instructions_file` is a separate runtime selector
      # (full/small/`cfg.modelInstructionsFile`), not part of this layer set.
      promptLayers = {
        common = {
          preamble.add = [ preprompt ];
          context.replace = [ agents.context ];
        };
        byVariant.serena.preamble.add = [ serenaInstructions ];
      };
      mkResolvedPrompt =
        variant:
        agents.mkPrompt {
          inherit pkgs;
          harness = "codex";
          model = "default";
          inherit variant;
          layers = promptLayers;
        };
      resolvedPrompts = {
        plain = mkResolvedPrompt "plain";
        serena = mkResolvedPrompt "serena";
      };
      bashLanguageServerWithShellcheck = pkgs.writeShellApplication {
        name = "bash-language-server-with-shellcheck";
        runtimeInputs = [ pkgs.nodejs ];
        text = ''
          export SHELLCHECK_PATH=${lib.getExe pkgs.shellcheck}
          exec ${lib.getExe pkgs.bash-language-server} "$@"
        '';
      };
      mkNodeLanguageServerWrapper =
        name: executable:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = [ pkgs.nodejs ];
          text = ''
            exec ${executable} "$@"
          '';
        };
      jsonLanguageServer = mkNodeLanguageServerWrapper "json-language-server" (
        lib.getExe' pkgs.vscode-langservers-extracted "vscode-json-language-server"
      );
      yamlLanguageServer = mkNodeLanguageServerWrapper "yaml-language-server" (
        lib.getExe' pkgs.yaml-language-server "yaml-language-server"
      );
      serenaHome = "${config.home.homeDirectory}/.serena-cxs";
      serenaConfig = pkgs.writeText "serena-cxs-config.yml" ''
        projects: []
        ls_specific_settings:
          bash:
            ls_path: ${lib.getExe bashLanguageServerWithShellcheck}
          json:
            ls_path: ${lib.getExe jsonLanguageServer}
          markdown:
            ls_path: ${lib.getExe pkgs.marksman}
          yaml:
            ls_path: ${lib.getExe yamlLanguageServer}
      '';

      proxyUrl = "http://${proxy.address}:${toString proxy.port}/v1";
      baseOverrides = [
        "openai_base_url=${builtins.toJSON proxyUrl}"
        "developer_instructions=${builtins.toJSON resolvedPrompts.plain.preamble}"
        "mcp_servers.headroom.command=${builtins.toJSON (lib.getExe headroomPackage)}"
        "mcp_servers.headroom.args=${builtins.toJSON [ "mcp" "serve" ]}"
      ];
      serenaOverrides = [
        "developer_instructions=${builtins.toJSON resolvedPrompts.serena.preamble}"
        "mcp_servers.serena.startup_timeout_sec=15"
        "mcp_servers.serena.command=${builtins.toJSON (lib.getExe serena)}"
        "mcp_servers.serena.env.SERENA_HOME=${builtins.toJSON serenaHome}"
        "mcp_servers.serena.args=${builtins.toJSON [
          "start-mcp-server"
          "--project-from-cwd"
          "--context=codex"
          "--open-web-dashboard"
          "False"
        ]}"
      ];
      mkOverrideArgs =
        values:
        lib.concatMapStringsSep "\n" (value: ''
          # shellcheck disable=SC2016 # Config values are intentionally literal.
          codex_args+=( -c ${lib.escapeShellArg value} )
        '') values;

      # Case arms handed to `agents.mkSelectorLoop`; `--cx-help`/`--`/catch-all
      # are the loop's own job, not the harness's — see selector-loop.nix.
      codexCaseArms = ''
            luna) model="gpt-5.6-luna" ;;
            terra) model="gpt-5.6-terra" ;;
            sol) model="gpt-5.6-sol" ;;
            lo|low) effort="low" ;;
            med|medium) effort="medium" ;;
            hi|high) effort="high" ;;
            xhi|xhigh) effort="xhigh" ;;
            full) instruction_file="" ;;
            small) instruction_file=${lib.escapeShellArg (toString instructionFiles.small)} ;;
            user) reviewer="user" ;;
            auto) reviewer="auto_review" ;;
      '';

      mkCodexWrapper =
        name: withSerena:
        agents.mkHarnessWrappers pkgs {
          inherit name;
          runtimeInputs = cliBase ++ cliTools ++ [ pkgs.systemd ];
          nativeText = ''
            # Harmless if Codex never exports its own `find` shell function
            # the way Claude does — the guard then just wraps plain
            # findutils. See `findGuardBashEnv`'s doc comment (`libagents.nix`).
            export BASH_ENV=${agents.findGuardBashEnv pkgs}

            model=""
            effort=""
            instruction_file=${lib.escapeShellArg (if cfg.modelInstructionsFile == null then "" else toString cfg.modelInstructionsFile)}
            reviewer=""
            passthrough=()

            ${agents.mkSelectorLoop {
              caseArms = codexCaseArms;
              helpFlag = "--cx-help";
              helpLines = [
                "usage: ${name} [luna|terra|sol] [lo|med|hi|xhi] [full|small] [user|auto] [--] [codex arguments...]"
              ];
              argsVar = "passthrough";
            }}

            if ! systemctl --user --quiet is-active headroom-proxy.service; then
              if systemctl --user --quiet cat headroom-proxy.service >/dev/null 2>&1; then
                systemctl --user start headroom-proxy.service
              else
                # The agent VM intentionally runs no Home Manager, so create
                # the equivalent service in its user manager. The transient
                # unit is shared by concurrent Codex sessions in this guest.
                systemd-run --user --quiet --collect \
                  --unit=headroom-proxy.service \
                  --property=Restart=on-failure \
                  --property=RestartSec=2 \
                  --setenv=HEADROOM_OUTPUT_SHAPER=${if proxy.shape-output then "1" else "0"} \
                  ${lib.getExe headroomPackage} proxy \
                    --host ${lib.escapeShellArg proxy.address} \
                    --port ${toString proxy.port} \
                  || systemctl --user --quiet is-active headroom-proxy.service
              fi
            fi

            codex_args=()
            ${mkOverrideArgs (baseOverrides ++ lib.optionals withSerena serenaOverrides)}

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

            # automatically trust the working-directory
            codex_args+=( -c "projects={\"$PWD\"={trust_level=\"trusted\"}}")

            exec ${lib.getExe codexPackage} "''${codex_args[@]}" "''${passthrough[@]}"
          '';

          sandbox = native: ''
            case "''${1:-}" in
              --cx-help)
                exec ${lib.getExe native} "$@"
                ;;
            esac

            cwd="$(${pkgs.coreutils}/bin/realpath "$PWD")"
            in_root=0
            sandbox_writable=(
              ${lib.concatMapStringsSep "\n              " (root: ''"${root}"'') sandboxWritableRoots}
            )

            for root in "''${sandbox_writable[@]}"; do
              [[ -d "$root" ]] || continue
              root="$(${pkgs.coreutils}/bin/realpath "$root")"
              if [[ "$cwd" == "$root" || "$cwd" == "$root"/* ]]; then
                in_root=1
                break
              fi
            done

            if [[ "$in_root" -ne 1 ]]; then
              echo "${name}: refusing to run $cwd in the agent VM — it is outside every shared root:" >&2
              printf '  %s\n' "''${sandbox_writable[@]}" >&2
              echo "cd into one of them, or run ${name}-native to bypass the VM instead." >&2
              exit 1
            fi

            # Herdr cannot see the guest's process tree through ssh. Its
            # foreground-process hint preserves agent status notifications.
            export HERDR_AGENT=codex
            exec agent-vm-session -- \
              bash -c 'cd "$1" && shift && exec "$@"' bash "$cwd" \
              ${lib.getExe native} "$@"
          '';
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
            lib.nameValuePair
              (builtins.replaceStrings [ "/home/user" ] [ config.home.homeDirectory ] name)
              (normalizeSettingsValue nestedValue)
          ) value
        else
          value;
      referenceSettings = builtins.removeAttrs (
        normalizeSettingsValue (builtins.fromTOML (self.data.read "programs/codex/config.toml"))
      ) [ "model_instructions_file" ];
      defaultSettings = lib.mapAttrsRecursive (_: lib.mkDefault) referenceSettings;
      skillsRoot = self.data.path "agents/skills";
    in
    {
      imports = [
        inputs.self.modules.homeManager.headroom
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
        services.headroom-proxy.enable = lib.mkDefault true;

        home.packages =
          let
            cxWrappers = mkCodexWrapper "cx" false;
            cxsWrappers = mkCodexWrapper "cxs" true;
          in
          [
            cxWrappers.native
            cxWrappers.wrapped
            cxsWrappers.native
            cxsWrappers.wrapped
          ];
        home.file.".serena-cxs/serena_config.yml" = {
          force = true;
          source = serenaConfig;
        };

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
