{ inputs, self, ... }:

{
  flake.modules.homeManager.claude-code =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      claudePackage = config.programs.claude-code.finalPackage;
      headroomPackage = inputs.alpkgs.packages.${pkgs.stdenv.hostPlatform.system}.headroom;
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
      cliToolsList = lib.concatMapStringsSep "\n" (
        tool: "- `${builtins.baseNameOf (lib.getExe tool)}`"
      ) cliTools;
      shellInstructions = ''
        # Shell

        Your shell environment is equipped with the following tools:

        ${cliToolsList}

        Run `tldr <program>` to see usage examples.

        ## RTK Rules

        Rust Token Killer reduces CLI context usage. It's always safe to use: if rtk has no filter for a command, it passes through unchanged.

        - Always prefix shell commands with rtk, except exact-content reads used to prepare an edit or verify a patch. Those reads must use the raw command to preserve punctuation and whitespace.
        - In command chains, prefix each segment: `rtk git add . && rtk git commit -m "msg"`
        - For debugging, use the raw command without an rtk prefix
        - `rtk proxy <cmd>` runs a command without filtering but tracks usage
      '';
      memoryInstructions = ''
        # Memory

        The per-project memory index is `MEMORY.md`, a *sibling* of the
        `memory/` directory (`.../projects/<project>/MEMORY.md`), not inside
        it (`.../projects/<project>/memory/MEMORY.md`). Check the correct
        path before concluding memory is missing or unwritable.
      '';
      skillsRoot = self.data.path "agents/skills";
      collectSkills =
        relativeDirectory:
        let
          directory = "${skillsRoot}${lib.optionalString (relativeDirectory != "") "/${relativeDirectory}"}";
        in
        lib.concatMapAttrs (
          entryName: entryType:
          let
            relativePath = if relativeDirectory == "" then entryName else "${relativeDirectory}/${entryName}";
            entryPath = "${skillsRoot}/${relativePath}";
          in
          if entryType != "directory" then
            { }
          else if builtins.pathExists "${entryPath}/SKILL.md" then
            { ${builtins.replaceStrings [ "/" ] [ "-" ] relativePath} = entryPath; }
          else
            collectSkills relativePath
        ) (builtins.readDir directory);
      # The built-in tool catalogue is the largest single block of the prompt
      # preamble: measured with `claude -p ok --output-format json`, the full
      # set costs ~10.8k of an ~18.3k floor. `--tools` replaces it with a
      # chosen subset, and the skill catalogue only loads alongside the `Skill`
      # tool, so an entry dropped here removes its documentation too.
      #
      # Kept: the four working tools and `WebSearch`, which has no shell
      # equivalent. Dropped: subagent and scheduling tools (`Agent`, `Task*`,
      # `Cron*`, `Monitor`, `SendMessage`), `WebFetch` (`curl` covers it), and
      # `Glob`/`Grep` (`rg`/`fd` cover them).
      #
      # `Skill` is behind the `skills` selector because typing `/<skill-name>`
      # loads a skill whether or not the tool is present; the tool only lets
      # the model reach for one unprompted, and it drags the whole catalogue
      # (~2.1k, of which ~1.4k is the bundled skills) in with it.
      #
      # Further levers, none used here, all documented at
      # <https://code.claude.com/docs/en/tools> and `/settings`:
      #   --system-prompt[-file]    replace rather than append the preamble; the analogue of codex `model_instructions_file`
      #   --settings <json|file>    per-invocation settings, like codex `-c`
      #   --setting-sources         restrict to user/project/local settings
      #   --disallowedTools         subtract from the catalogue instead of replacing it; also removes the schema
      #   --disable-slash-commands  drop every skill, bundled or not (~2k)
      defaultTools = [
        "Bash"
        "Read"
        "Edit"
        "Write"
        "WebSearch"
      ];
      # Plan mode is unusable without the tools that enter and leave it.
      planTools = [
        "EnterPlanMode"
        "ExitPlanMode"
      ];
      skillTools = [ "Skill" ];
      mkClaudeWrapper =
        name: withSerena:
        pkgs.writeShellApplication {
          inherit name;
          excludeShellChecks = [ "SC2016" ];
          runtimeInputs = [
            claudePackage
            headroomPackage
            pkgs.rtk
            pkgs.tlrc
          ]
          ++ cliTools;
          text = ''
            model=""
            effort=""
            permission_mode=""
            tools=${lib.escapeShellArg (lib.concatStringsSep "," defaultTools)}
            skills=0
            headroom_args=(
              --code-memory ${if withSerena then "serena" else "none"}
              --tool-search true
              ${lib.optionalString withSerena "--serena-instructions"}
            )
            claude_args=()

            while (( $# )); do
              case "$1" in
                haiku|sonnet|opus) model="$1" ;;
                lo|low) effort="low" ;;
                med|medium) effort="medium" ;;
                hi|high) effort="high" ;;
                max) effort="max" ;;
                user|manual) permission_mode="manual" ;;
                edits|acceptEdits) permission_mode="acceptEdits" ;;
                auto) permission_mode="auto" ;;
                plan) permission_mode="plan" ;;
                bypass) permission_mode="bypassPermissions" ;;
                memory) headroom_args+=( --memory ) ;;
                graph|code-graph) headroom_args+=( --code-graph ) ;;
                1m) headroom_args+=( --1m ) ;;
                search|tool-search) headroom_args+=( --tool-search auto ) ;;
                alltools|all-tools) tools="default" ;;
                skill|skills) skills=1 ;;
                --cc-help)
                  echo "usage: ${name} [haiku|sonnet|opus] [lo|med|hi|max] [user|edits|auto|plan|bypass] [memory|graph|1m|search|skills|alltools] [--] [claude arguments...]"
                  echo "skills adds the Skill tool and its catalogue; /<skill-name> works without it"
                  echo "selectors are recognized in any order before --; later selectors replace earlier ones"
                  exit 0
                  ;;
                --)
                  shift
                  claude_args+=( "$@" )
                  break
                  ;;
                *) claude_args+=( "$1" ) ;;
              esac
              shift
            done

            [[ -z "$model" ]] || claude_args+=( --model "$model" )
            [[ -z "$effort" ]] || claude_args+=( --effort "$effort" )
            [[ -z "$permission_mode" ]] || claude_args+=( --permission-mode "$permission_mode" )

            if [[ "$tools" != "default" ]]; then
              [[ "$permission_mode" != "plan" ]] || tools+=",${lib.concatStringsSep "," planTools}"
              (( ! skills )) || tools+=",${lib.concatStringsSep "," skillTools}"
            fi
            [[ "$tools" == "default" ]] || claude_args+=( --tools "$tools" )

            claude_args+=( --append-system-prompt ${lib.escapeShellArg shellInstructions} )
            claude_args+=( --append-system-prompt ${lib.escapeShellArg memoryInstructions} )

            exec ${lib.getExe headroomPackage} wrap claude "''${headroom_args[@]}" -- "''${claude_args[@]}"
          '';
        };
    in
    {
      home.packages = [
        (mkClaudeWrapper "cc" false)
        (mkClaudeWrapper "ccs" true)
      ];

      programs.claude-code = {
        enable = lib.mkDefault true;
        context = self.data.read "agents/AGENTS.md";
        skills = collectSkills "";
        settings = {
          includeCoAuthoredBy = lib.mkDefault false;
          permissions.defaultMode = lib.mkDefault "manual";
        };
      };
    };
}
