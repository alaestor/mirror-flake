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

        The per-project memory index is `MEMORY.md`, *inside* the `memory/`
        directory (`.../projects/<project>/memory/MEMORY.md`), alongside the
        memory files it indexes, and its links are relative to that directory.
        Check that path before concluding memory is missing or unwritable.
      '';

      # `--system-prompt-file` replaces the preamble wholesale: verified against
      # a capture proxy, it swaps exactly the third `system` block (~9.2k chars)
      # and leaves the two small unoverridable ones alone. See the verbatim
      # `data/programs/claude/*-full.md` the mini version was cut down from.
      # The prompt contains dynamic environment data we inject via our wrapper
      miniPrompt = self.data.path "programs/claude/claude-instructions-mini.md";

      # Claude Code derives the memory directory from the project root, slugged
      # by replacing `/` and `.` with `-`; `/mnt/Vault/.dotfiles/flake` becomes
      # `-mnt-Vault--dotfiles-flake`. Reproduced here because the mini prompt
      # points at the directory by name and the stock text is gone.
      environmentBlock = ''
        cc_environment_block() {
          local root slug status_text
          root="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")"
          slug="''${root//[\/.]/-}"

          printf '# Environment\n'
          printf ' - Primary working directory: %s\n' "$PWD"
          printf ' - Is a git repository: %s\n' \
            "$(git rev-parse --is-inside-work-tree 2>/dev/null || printf 'false')"
          printf ' - Platform: %s\n' "$(uname -s | tr '[:upper:]' '[:lower:]')"
          printf ' - Shell: bash\n'
          printf ' - OS Version: %s %s\n' "$(uname -s)" "$(uname -r)"
          printf ' - Persistent memory directory: %s\n' \
            "$HOME/.claude/projects/$slug/memory"

          git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

          status_text="$(git status --porcelain 2>/dev/null)"
          printf '\ngitStatus: snapshot taken at the start of the conversation; it does not update.\n'
          printf '\nCurrent branch: %s\n' "$(git branch --show-current 2>/dev/null)"
          printf '\nStatus:\n%s\n' "''${status_text:-(clean)}"
          printf '\nRecent commits:\n%s\n' "$(git log --oneline -5 2>/dev/null)"
        }
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
      # The tool catalogue rivals the preamble in size. `--tools` replaces it
      # with a chosen subset, and the skill catalogue only loads alongside the
      # `Skill` tool, so an entry dropped here takes its documentation with it.
      #
      # Kept: the four working tools and `WebSearch`, which has no shell
      # equivalent. Dropped: subagent and scheduling tools (`Agent`, `Task*`,
      # `Cron*`, `Monitor`, `SendMessage`), `WebFetch` (`curl` covers it), and
      # `Glob`/`Grep` (`rg`/`fd` cover them).
      #
      # `Skill` is behind the `skills` selector because typing `/<skill-name>`
      # loads a skill whether or not the tool is present; the tool only lets
      # the model reach for one unprompted, and it drags the whole catalogue
      # in with it.
      #
      # For what any of this costs, ask the binary rather than guessing:
      # `nix run .#extract-system-prompt-claude -- --report --model sonnet`.
      #
      # Further levers, none used here, all documented at
      # <https://code.claude.com/docs/en/tools> and `/settings`:
      #   --settings <json|file>    per-invocation settings, like codex `-c`
      #   --setting-sources         restrict to user/project/local settings
      #   --disallowedTools         subtract from the catalogue instead of replacing it; also removes the schema
      #   --disable-slash-commands  drop every skill, bundled or not
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
      # Auto-compaction summarizes for narrative continuity and loses the
      # details needed to resume work. This guard replaces it: an agent-written
      # handoff at ~65% of the window, and a hard turn stop at ~92.5% so a
      # session can never run past the limit trying to produce one. See the
      # script for the threshold environment variables.
      contextGuard = pkgs.writers.writePython3Bin "cc-context-guard" {
        flakeIgnore = [ "E501" ];
      } (self.data.read "agents/context-guard.py");
      guardCommand = [
        {
          type = "command";
          command = lib.getExe contextGuard;
        }
      ];
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
            ${environmentBlock}
            model=""
            effort=""
            permission_mode=""
            prompt="mini"
            lean_tools=1
            tools=${lib.escapeShellArg (lib.concatStringsSep "," defaultTools)}
            skills=0
            context_limit=200000
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
                1m)
                  headroom_args+=( --1m )
                  context_limit=1000000
                  ;;
                search|tool-search) headroom_args+=( --tool-search auto ) ;;
                alltools|all-tools) tools="default" ;;
                skill|skills) skills=1 ;;
                full|full-prompt) prompt="full" ;;
                mini|mini-prompt) prompt="mini" ;;
                lean|lean-tools) lean_tools=1 ;;
                verbose|verbose-tools) lean_tools=0 ;;
                --cc-help)
                  echo "usage: ${name} [haiku|sonnet|opus] [lo|med|hi|max] [user|edits|auto|plan|bypass] [mini|full] [lean|verbose] [memory|graph|1m|search|skills|alltools] [--] [claude arguments...]"
                  echo "mini (default) replaces the stock preamble with a trimmed one; full keeps Claude Code's"
                  echo "lean (default) gives every model Opus's terse tool descriptions; verbose keeps the stock ones"
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

            if [[ "$prompt" != "full" ]]; then
              claude_args+=( --system-prompt-file ${lib.escapeShellArg (toString miniPrompt)} )
              claude_args+=( --append-system-prompt "$(cc_environment_block)" )
            fi

            claude_args+=( --append-system-prompt ${lib.escapeShellArg shellInstructions} )
            claude_args+=( --append-system-prompt ${lib.escapeShellArg memoryInstructions} )

            # `--autocompact` has no `off`; parking it at the maximum keeps
            # Claude Code from attempting a proactive compaction the PreCompact
            # guard would only have to block. The guard stops the turn first.
            claude_args+=( --autocompact 1M )

            # Every tool description ships in a terse and a verbose variant,
            # picked by a gate that only Opus passes: for the default set the
            # verbose one runs 19,578 chars against 7,774. This variable
            # overrides the gate for any model, so Sonnet gets the same text
            # Opus has been running all along. Always set explicitly, never
            # inherited, so a stray value in the caller's shell cannot quietly
            # change what the model reads. `verbose` restores the stock gate.
            export CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT="$lean_tools"

            # Hooks inherit this environment; the context guard reads it to
            # scale its thresholds to the session's actual window.
            export CC_CONTEXT_LIMIT="$context_limit"

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
          skipDangerousModePermissionPrompt = lib.mkDefault true;
          permissions.defaultMode = lib.mkDefault "bypassPermissions";
          # The away recap spends a background model call to restate a session
          # we were present for. Equivalent to `CLAUDE_CODE_ENABLE_AWAY_SUMMARY`.
          awaySummaryEnabled = lib.mkDefault false;
          hooks = {
            # PostToolUse is the only event that fires mid-turn often enough to
            # catch the ceiling before a long turn overruns it.
            PostToolUse = [ { hooks = guardCommand; } ];
            # Covers turns that cross the warning threshold without a tool call.
            Stop = [ { hooks = guardCommand; } ];
            # Names any prior handoff so it can be referred to without a path.
            SessionStart = [ { hooks = guardCommand; } ];
            # Manual `/compact` stays available; only automatic runs are blocked.
            PreCompact = [
              {
                matcher = "auto";
                hooks = guardCommand;
              }
            ];
          };
        };
      };
    };
}
