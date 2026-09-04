/**
  Claude Code, wrapped so its environment/state paths agree with the
  agent-vm guest (see docs/agents.md's "Shared state" section).
*/
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

      # `CLAUDE_CONFIG_DIR` relocates `~/.claude.json` into `~/.claude`, so
      # virtiofs (directory-only sharing) can carry it along with the rest of
      # claude's state. Set here, not just in the wrapper, so a bare `claude`
      # or an editor extension agrees with the wrappers and the VM guest
      # (`agent-vm.guestEnvironment`) about where state lives.
      claudeEnvironment = agents.environmentFor config.home.homeDirectory;

      # Carries the host's rendered git config into the guest; see
      # `gitEnvironmentText`'s comment (`libagents.nix`) for why it is baked
      # into the wrapper rather than routed through `guestEnvironment`.
      # Signing still goes through the gpg-agent channel's restricted socket;
      # no key material is in this file, only identity and a signer path that
      # resolves in the guest.
      gitEnvironment = agents.gitEnvironmentText config;

      # The relocation is undocumented and version-dependent (anthropics/
      # claude-code#3833); an older claude keeps writing `~/.claude.json`
      # outside every share, so the guest would silently start blank. Fail
      # the build instead.
      minimumClaudeVersion = "2.0.42";
      claudeVersionOk = !lib.versionOlder claudePackage.version minimumClaudeVersion;
      headroomPackage = inputs.alpkgs.packages.${pkgs.stdenv.hostPlatform.system}.headroom;
      serenaPackage = inputs.alpkgs.packages.${pkgs.stdenv.hostPlatform.system}.serena;
      # Matches `stateDirs.serena` (`libagents.nix`) — serena's own default
      # `SERENA_HOME` when nothing overrides it. Set explicitly here so this
      # file states the fact rather than leaning on serena's undocumented
      # default staying what it is.
      serenaHome = "${config.home.homeDirectory}/.serena";
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

        # Claude Code only auto-loads CLAUDE.md, with no fallback to AGENTS.md
        # (anthropics/claude-code#6235/#34235 — still open, no native support).
        # This reproduces that missing behavior: find AGENTS.md at the project
        # root and fold it into the appended system prompt, same as an
        # imported CLAUDE.md would have been. `noagentsmd` skips this.
        cc_agents_md() {
          local root file
          root="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")"
          file="$root/AGENTS.md"
          [[ -f "$file" ]] || return 0
          printf '# AGENTS.md (%s)\n\n' "$file"
          cat "$file"
        }
      '';

      # Sessions isolate through the agent VM — `sandboxPackage`/
      # `sandboxToolPath` (the vendored bubblewrap sandbox's own PATH
      # reconstruction, needed because it clears the environment) are gone
      # from this file along with the bubblewrap `sandbox` function they only
      # served; `modules/mechanisms/claude-sandbox.nix` and
      # `data/utils/claude-sandbox/` are gone too, having been kept around
      # only as a fallback in case the VM migration didn't work out.
      #
      # The only paths a session may work in. `agent-vm.projectRoots`
      # (`hosts/apc/system.nix`) shares exactly these two trees into the
      # guest — kept as the same list on purpose, so there is one fact
      # ("what the agent may work on"), not two that can drift apart. Unlike
      # bubblewrap's per-invocation bind mounts, virtiofs shares are fixed at
      # guest boot, so a session is refused outside these roots rather than
      # the list being able to widen itself to wherever `$PWD` happens to be.
      sandboxWritableRoots = agents.sandboxWritableRootsFor "$HOME";

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
      # details needed to resume work. This guard replaces it: a single
      # threshold, sitting just under Claude Code's own auto-compact reserve
      # (~83% of the window), so the agent writes a handoff and the turn
      # stops right where native compaction would otherwise have kicked in.
      # See the script for the threshold environment variables.
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
            noagentsmd) agents_md=0 ;;
            full|full-prompt) prompt="full" ;;
            mini|mini-prompt) prompt="mini" ;;
            lean|lean-tools) lean_tools=1 ;;
            verbose|verbose-tools) lean_tools=0 ;;
      '';

      # `--mcp-config` + `--strict-mcp-config` (below) replace whatever
      # `mcpServers` happens to be sitting in the live, auth-bearing
      # `~/.claude/.claude.json` — that file is runtime state `claude mcp
      # add` writes to, not something this module manages, and its entries
      # apply to every session regardless of which wrapper started it (there
      # is no `cc`/`ccs` distinction once a server lands there). Building the
      # server list here instead means each wrapper's MCP set is exactly what
      # `withSerena` says it is, and `lib.getExe` keeps every command pointed
      # at the flake's *current* package rather than a store path frozen at
      # whatever version was live when someone last ran `claude mcp add`.
      mcpServersBase = {
        headroom = {
          type = "stdio";
          command = lib.getExe headroomPackage;
          args = [
            "mcp"
            "serve"
          ];
        };
      };
      mcpServersSerena = mcpServersBase // {
        serena = {
          type = "stdio";
          command = lib.getExe serenaPackage;
          args = [
            "start-mcp-server"
            "--project-from-cwd"
            "--context=claude-code"
            "--open-web-dashboard"
            "False"
          ];
          env = {
            SERENA_HOME = serenaHome;
          };
        };
      };
      mkMcpConfig =
        name: servers:
        pkgs.writeText "${name}-mcp-config.json" (builtins.toJSON { mcpServers = servers; });
      mcpConfigPlain = mkMcpConfig "cc" mcpServersBase;
      mcpConfigSerena = mkMcpConfig "ccs" mcpServersSerena;

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
            # Exported rather than inherited from the session: a wrapper that
            # only works in a login shell that happened to source Home
            # Manager's session variables is a wrapper that breaks over ssh
            # into the agent VM, which is exactly where it matters most.
            #
            # Resolved against the *runtime* $HOME, not baked in as a literal
            # path: `cc` execs this same `nativeText` over ssh inside the
            # agent VM guest (Phase 8), whose user shares `hostUser`'s name
            # and home path (`vm.nix`) — so `$HOME` happens to already agree
            # with the host today, but staying dynamic is what keeps that
            # true if it ever doesn't, rather than baking in an assumption
            # that would silently present as a fresh, logged-out install the
            # day it stops holding.
            export CLAUDE_CONFIG_DIR="$HOME/.claude"
            ${gitEnvironment}

            # Claude's Bash tool exports its own `find` -> bfs shell function
            # into every subprocess it spawns, which does not itself refuse a
            # literal `/` root; this wraps it (or plain findutils, if nothing
            # claimed the name) with a guard against that one case. See
            # `findGuardBashEnv`'s doc comment (`libagents.nix`).
            export BASH_ENV=${agents.findGuardBashEnv pkgs}

            # Backstop for the eval-time assertion, which cannot see the
            # `-74` build suffix the behaviour actually landed in and which
            # says nothing at all about a claude that arrived some other way
            # (a `npm -g` install ahead of us on PATH). ~85ms, once per
            # launch, to not lose a credentials file silently.
            cc_version="$(claude --version 2>/dev/null | ${pkgs.coreutils}/bin/cut -d' ' -f1)"
            if [[ -n "$cc_version" ]] \
              && [[ "$(printf '%s\n' "$cc_version" ${lib.escapeShellArg minimumClaudeVersion} \
                | ${pkgs.coreutils}/bin/sort -V | ${pkgs.coreutils}/bin/head -n1)" != ${lib.escapeShellArg minimumClaudeVersion} ]]
            then
              echo "${name}: claude $cc_version predates CLAUDE_CONFIG_DIR support (need ${minimumClaudeVersion}+);" >&2
              echo "  ~/.claude.json would not follow the config directory. Refusing to start." >&2
              exit 1
            fi

            model=""
            effort=""
            permission_mode=""
            prompt="mini"
            lean_tools=1
            tools=${lib.escapeShellArg (lib.concatStringsSep "," defaultTools)}
            skills=0
            agents_md=1
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
                "${name} isolates sessions in the agent VM by default; run ${name}-native directly to bypass it entirely"
                "VM sessions may only run in ${lib.concatStringsSep " and " sandboxWritableRoots}"
                "skills adds the Skill tool and its catalogue; /<skill-name> works without it"
                "noagentsmd skips injecting the project root's AGENTS.md, if any"
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
            if (( agents_md )); then
              agents_md_text="$(cc_agents_md)"
              [[ -z "$agents_md_text" ]] || append_prompt="$append_prompt"$'\n\n'"$agents_md_text"
            fi
            claude_args+=( --append-system-prompt "$append_prompt" )

            # Fully replaces whatever `mcpServers` the live `~/.claude/.claude.json`
            # happens to hold — see `mcpServersBase`/`mcpServersSerena` above.
            claude_args+=(
              --strict-mcp-config
              --mcp-config ${lib.escapeShellArg (toString (if withSerena then mcpConfigSerena else mcpConfigPlain))}
            )

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
          #
          # Sessions isolate through the agent VM (`agent-vm-session`) instead
          # of bubblewrap. `agent-vm.projectRoots` (`hosts/apc/system.nix`) is
          # the guest-side equivalent of `sandboxWritableRoots` below — kept
          # as the same two paths deliberately, so both lists describe one
          # fact ("what the agent may work on") rather than drifting apart.
          # Unlike bubblewrap's per-invocation `--extra-bind`, virtiofs
          # shares are fixed at guest boot, so there is nothing to bind here
          # — only a membership check against what was already shared.
          sandbox = native: ''
            case "''${1:-}" in
              --cc-help)
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

            # `agent-vm-session` lands an ssh session in the guest user's
            # $HOME, not $PWD — `cd` explicitly before handing off, since the
            # project tree is shared at the identical host path (`vm-host.nix`
            # `projectRoots`) and is therefore reachable under the same
            # `$cwd` inside the guest. `bash -c ... bash "$cwd" <native> "$@"`
            # rather than a literal `cd "$cwd" &&` string: `agent-vm-session`
            # re-quotes every argument it receives independently
            # (`printf %q`), so building the remote command as real argv
            # entries here — not a hand-assembled string — is what keeps that
            # quoting correct end to end.
            # Herdr cannot see the guest's process tree through ssh. Its
            # foreground-process hint preserves agent status notifications.
            export HERDR_AGENT=claude
            exec agent-vm-session -- \
              bash -c 'cd "$1" && shift && exec "$@"' bash "$cwd" \
              ${lib.getExe native} "$@"
          '';
        };

      ccWrappers = mkClaudeWrapper "cc" false;
      ccsWrappers = mkClaudeWrapper "ccs" true;
    in
    {
      imports = [ inputs.self.modules.homeManager.agents-prompt-preview ];

      assertions = [
        {
          assertion = claudeVersionOk;
          message = ''
            claude-code ${claudePackage.version} predates the version where
            CLAUDE_CONFIG_DIR relocates ~/.claude.json (v${minimumClaudeVersion}-74). The
            agent VM shares a single config directory and would silently lose
            that file. See https://github.com/anthropics/claude-code/issues/3833
          '';
        }
      ];

      home.sessionVariables = claudeEnvironment;

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
