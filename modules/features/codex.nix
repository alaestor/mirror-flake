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
      cfg = config.codex;
      proxy = config.services.headroom-proxy;
      codexPackage = config.programs.codex.package;
      headroomPackage = proxy.package;

      instructionFiles = {
        full = self.data.path "programs/codex/codex-instructions-gpt-5-full.md";
        # Short outward-facing names keep `medium` available for reasoning effort.
        small = self.data.path "programs/codex/codex-instructions-gpt-5-medium.md";
        tiny = self.data.path "programs/codex/codex-instructions-gpt-5-small.md";
      };

      cliBase = with pkgs; [
        rtk
        tlrc
      ];

      cliTools = with pkgs; [
        ripgrep
        jq
        yq-go
        fd
        fzf
        sd
        eza
        grex
        difftastic
        xh
        doggo
        bat
        tree
        taplo
        pandoc
        shellcheck
        hyperfine
        tokei
        procs
        dust
      ];

      cliToolsList = lib.concatMapStringsSep "\n" (tool: "- `${builtins.baseNameOf (lib.getExe tool)}`") cliTools;

      preprompt = ''
        # Shell

        Your environment is equipped with the following tools:

        ${cliToolsList}

        Run `tldr <program>` to see usage examples.

        ## RTK Rules

        Rust Token Killer reduces CLI context usage. It's always safe to use: if rtk has no filter for a command, it passes through unchanged.

        - When running shell commands, **always prefix with `rtk`**
        - In command chains, prefix each segment: `rtk git add . && rtk git commit -m "msg"`
        - For debugging, use the raw command without an rtk prefix
        - `rtk proxy <cmd>` runs a command without filtering but tracks usage
      '';

      serena = inputs.alpkgs.packages.${pkgs.stdenv.hostPlatform.system}.serena;
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
        "developer_instructions=${builtins.toJSON preprompt}"
        "mcp_servers.headroom.command=${builtins.toJSON (lib.getExe headroomPackage)}"
        "mcp_servers.headroom.args=${builtins.toJSON [ "mcp" "serve" ]}"
      ];
      serenaOverrides = [
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

      mkCodexWrapper =
        name: withSerena:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = cliBase ++ cliTools ++ [ pkgs.systemd ];
          text = ''
            model=""
            effort=""
            instruction_file=${lib.escapeShellArg (if cfg.modelInstructionsFile == null then "" else toString cfg.modelInstructionsFile)}
            passthrough=()

            while (( $# > 0 )); do
              case "$1" in
                luna) model="gpt-5.6-luna" ;;
                terra) model="gpt-5.6-terra" ;;
                sol) model="gpt-5.6-sol" ;;
                lo|low) effort="low" ;;
                med|medium) effort="medium" ;;
                hi|high) effort="high" ;;
                xhi|xhigh) effort="xhigh" ;;
                full) instruction_file=${lib.escapeShellArg (toString instructionFiles.full)} ;;
                small) instruction_file=${lib.escapeShellArg (toString instructionFiles.small)} ;;
                tiny) instruction_file=${lib.escapeShellArg (toString instructionFiles.tiny)} ;;
                --cx-help)
                  echo "usage: ${name} [luna|terra|sol] [lo|med|hi|xhi] [full|small|tiny] [--] [codex arguments...]"
                  echo "selectors are recognized in any order before --; later selectors replace earlier ones"
                  exit 0
                  ;;
                --)
                  shift
                  passthrough+=( "$@" )
                  break
                  ;;
                *) passthrough+=( "$1" ) ;;
              esac
              shift
            done

            if ! systemctl --user --quiet is-active headroom-proxy.service; then
              systemctl --user start headroom-proxy.service
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

            exec ${lib.getExe codexPackage} "''${codex_args[@]}" "''${passthrough[@]}"
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
      collectSkills =
        relativeDirectory:
        let
          directory = "${skillsRoot}${lib.optionalString (relativeDirectory != "") "/${relativeDirectory}"}";
        in
        lib.concatMapAttrs (
          entryName: entryType:
          let
            relativePath =
              if relativeDirectory == "" then entryName else "${relativeDirectory}/${entryName}";
            entryPath = "${skillsRoot}/${relativePath}";
          in
          if entryType != "directory" then
            { }
          else if builtins.pathExists "${entryPath}/SKILL.md" then
            {
              ${builtins.replaceStrings [ "/" ] [ "-" ] relativePath} = entryPath;
            }
          else
            collectSkills relativePath
        ) (builtins.readDir directory);
    in
    {
      imports = [ inputs.self.modules.homeManager.headroom ];

      # Quick references retained from the old README:
      # - `codex features list` shows current feature flags.
      # - Feature defaults for the referenced release:
      #   https://github.com/openai/codex/blob/rust-v0.145.0/codex-rs/features/src/lib.rs
      # - Configuration types for the referenced release:
      #   https://github.com/openai/codex/blob/rust-v0.145.0/codex-rs/config/src/config_toml.rs
      options.codex.modelInstructionsFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = instructionFiles.small;
        defaultText = lib.literalExpression "the bundled small instruction file";
        description = "Default model instruction file used by Codex and cx; null leaves it unset.";
      };

      config = {
        services.headroom-proxy.enable = lib.mkDefault true;

        home.packages = [
          (mkCodexWrapper "cx" false)
          (mkCodexWrapper "cxs" true)
        ];
        home.file.".serena-cxs/serena_config.yml".source = serenaConfig;

        programs.codex = {
          enable = lib.mkDefault true;
          context = self.data.read "agents/AGENTS.md";
          rules.default = self.data.path "programs/codex/default.rules";
          skills = collectSkills "";
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
