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
      agents = self.lib.agents;
      claudePackage = config.programs.claude-code.finalPackage;
      headroomPackage = inputs.alpkgs.packages.${pkgs.stdenv.hostPlatform.system}.headroom;
      cliTools = agents.tools pkgs;
      shellInstructions = agents.fragments.shell pkgs + "\n" + agents.fragments.headroom + "\n" + agents.fragments.rtk;

      memoryInstructions = agents.fragments.memory;

      # `--system-prompt-file` replaces the preamble wholesale: verified against
      # a capture proxy, it swaps exactly the third `system` block (~9.2k chars)
      # and leaves the two small unoverridable ones alone. See the verbatim
      # `data/programs/claude/*-full.md` the mini version was cut down from.
      # The prompt contains dynamic environment data we inject via our wrapper
      miniPrompt = self.data.path "programs/claude/claude-instructions-mini.md";

      # Nothing here varies by model or variant today (`withSerena` only
      # changes headroom_args, not prompt text) — `byVariant`/`byModel` stay
      # empty. Kept as layers anyway so a future addition has somewhere to go
      # without restructuring; see `flake.lib.agents.mkPrompt`.
      promptLayers = {
        common = {
          system = miniPrompt;
          preamble.add = [
            shellInstructions
            memoryInstructions
          ];
          context.replace = [ agents.context ];
        };
      };
      resolvedPrompt = agents.mkPrompt {
        inherit pkgs;
        harness = "claude";
        model = "default";
        variant = "plain";
        layers = promptLayers;
      };

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

      # Sessions run under the vendored bubblewrap sandbox by default; `nobox`
      # opts out. The sandbox clears the environment and builds PATH from its
      # own tool profile, so everything the prompt promises has to be handed
      # back explicitly: the tool list through `CLAUDE_SANDBOX_EXTRA_PATH`, and
      # our two variables through `env` in the sandboxed command itself, since
      # upstream only forwards host variables named in its config file.
      sandboxPackage = self.lib.mkClaudeSandbox pkgs;

      # The only paths a session may write. Everything else the host exposes,
      # `/nix/store` included, arrives through the sandbox's base `--ro-bind /
      # /` and stays read-only. The sandbox always binds its project directory
      # read-write, so a session is refused outside these roots rather than
      # silently widening the writable set to the working directory.
      sandboxWritableRoots = [
        "$HOME/Projects"
        "/mnt/Vault/.dotfiles/flake"
      ];
      sandboxToolPath = lib.makeBinPath (
        cliTools
        ++ [
          pkgs.rtk
          pkgs.tlrc
        ]
      );

      skillsRoot = self.data.path "agents/skills";
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
      # Case arms handed to `agents.mkSelectorLoop`; `--cc-help`/`--`/catch-all
      # are the loop's own job, not the harness's — see selector-loop.nix.
      claudeCaseArms = ''
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
      '';

      mkClaudeWrapper =
        name: withSerena:
        agents.mkHarnessWrappers pkgs {
          inherit name;
          runtimeInputs = [
            claudePackage
            headroomPackage
            pkgs.rtk
            pkgs.tlrc
          ]
          ++ cliTools;
          # `box`/`nobox` are gone: `cc-native` never sandboxes at all, and
          # running it directly *is* the bypass — see selector-loop.nix and
          # the handoff on Phase 3's redesign. This is an intentional
          # behavior change from the pre-split wrapper.
          nativeText = ''
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

            ${agents.mkSelectorLoop {
              caseArms = claudeCaseArms;
              helpFlag = "--cc-help";
              helpLines = [
                "usage: ${name} [haiku|sonnet|opus] [lo|med|hi|max] [user|edits|auto|plan|bypass] [mini|full] [lean|verbose] [memory|graph|1m|search|skills|alltools] [--] [claude arguments...]"
                "mini (default) replaces the stock preamble with a trimmed one; full keeps Claude Code's"
                "lean (default) gives every model Opus's terse tool descriptions; verbose keeps the stock ones"
                "${name} sandboxes sessions with bubblewrap by default; run ${name}-native directly to bypass it entirely"
                "sandboxed sessions may only write ${lib.concatStringsSep " and " sandboxWritableRoots}"
                "skills adds the Skill tool and its catalogue; /<skill-name> works without it"
              ];
              argsVar = "claude_args";
            }}

            [[ -z "$model" ]] || claude_args+=( --model "$model" )
            [[ -z "$effort" ]] || claude_args+=( --effort "$effort" )
            [[ -z "$permission_mode" ]] || claude_args+=( --permission-mode "$permission_mode" )

            if [[ "$tools" != "default" ]]; then
              [[ "$permission_mode" != "plan" ]] || tools+=",${lib.concatStringsSep "," planTools}"
              (( ! skills )) || tools+=",${lib.concatStringsSep "," skillTools}"
            fi
            [[ "$tools" == "default" ]] || claude_args+=( --tools "$tools" )

            # `--append-system-prompt` does not accumulate across repeated
            # flags — only the last one takes effect — so every appended
            # block has to be concatenated into a single call.
            append_prompt=${lib.escapeShellArg resolvedPrompt.preamble}
            if [[ "$prompt" != "full" ]]; then
              claude_args+=( --system-prompt-file ${lib.escapeShellArg (toString resolvedPrompt.system)} )
              append_prompt="$(cc_environment_block)"$'\n\n'"$append_prompt"
            fi
            claude_args+=( --append-system-prompt "$append_prompt" )

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

            session=(
              ${lib.getExe headroomPackage} wrap claude
              "''${headroom_args[@]}" -- "''${claude_args[@]}"
            )

            exec "''${session[@]}"
          '';

          # `cc`/`ccs` sandbox `cc-native`/`ccs-native` unconditionally —
          # there is no runtime opt-out selector any more; running the
          # `-native` package directly is the only bypass. `--cc-help` is
          # special-cased ahead of the sandbox check so it works from any
          # directory, matching the pre-split wrapper's behavior (it used to
          # exit before ever reaching the sandbox's cwd restriction).
          sandbox = native: ''
            case "''${1:-}" in
              --cc-help)
                exec ${lib.getExe native} "$@"
                ;;
            esac

            # Every writable root is bound in full, so a session can reach
            # sibling trees it needs; the project directory stays the working
            # directory so the model opens where the caller stands. Both must
            # agree: a working directory outside the roots would otherwise be
            # bound read-write as the project and defeat the restriction.
            cwd="$(${pkgs.coreutils}/bin/realpath "$PWD")"
            project=""
            sandbox_args=()
            sandbox_writable=(
              ${lib.concatMapStringsSep "\n              " (root: ''"${root}"'') sandboxWritableRoots}
            )

            for root in "''${sandbox_writable[@]}"; do
              [[ -d "$root" ]] || continue
              root="$(${pkgs.coreutils}/bin/realpath "$root")"
              sandbox_args+=( --extra-bind "$root" )
              if [[ "$cwd" == "$root" || "$cwd" == "$root"/* ]]; then
                project="$cwd"
              fi
            done

            if [[ -z "$project" ]]; then
              echo "${name}: refusing to sandbox $cwd — it is outside every writable root:" >&2
              printf '  %s\n' "''${sandbox_writable[@]}" >&2
              echo "cd into one of them, or run ${name}-native to bypass the sandbox instead." >&2
              exit 1
            fi

            export CLAUDE_SANDBOX_EXTRA_PATH=${lib.escapeShellArg sandboxToolPath}
            exec ${lib.getExe sandboxPackage} \
              "''${sandbox_args[@]}" \
              "$project" -- \
              ${lib.getExe native} "$@"
          '';
        };

      ccWrappers = mkClaudeWrapper "cc" false;
      ccsWrappers = mkClaudeWrapper "ccs" true;
    in
    {
      home.packages = [
        ccWrappers.native
        ccWrappers.wrapped
        ccsWrappers.native
        ccsWrappers.wrapped
      ];

      agents.promptPreview.claude.plain = resolvedPrompt;

      programs.claude-code = {
        enable = lib.mkDefault true;
        context = resolvedPrompt.context;
        skills = agents.collectSkills skillsRoot;
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
