/**
  # flake.lib.agents

  Shared definitions consumed by every harness feature module
  (`modules/features/claude-code.nix`, `modules/features/codex.nix`, and any
  future addition). This is the harness *layer*: it knows about tool lists,
  prompt fragments, skills and `AGENTS.md`. It must never mention vsock,
  virtiofs, systemd units, or anything belonging to the VM layer
  (`modules/mechanisms/libagents/vm.nix`) — see the layering rule in
  `docs/agents.md`.

  - `tools` / `toolsMarkdown` — the CLI tool set every harness's shell
    fragment advertises, and its rendering as a markdown bullet list.
  - `fragments` — reusable preamble text blocks (`shell`, `rtk`, `headroom`,
    `memory`, `serena`). Each is plain text; harnesses are responsible for
    concatenating the fragments they want and injecting the result at
    whatever depth their own module (`--append-system-prompt`,
    `developer_instructions=`, ...) requires.
  - `collectSkills` — recursively scans a skills root for `SKILL.md`
    directories, keyed by their path with `/` flattened to `-`.
  - `context` — the shared `AGENTS.md` context text.
  - `stateDirs` / `stateDirsFor` — the `$HOME`-relative directories each
    harness and component keeps live state in, and a helper that makes them
    absolute for one home. Declared here because the VM layer is forbidden
    from naming any of them and the
    harness modules themselves are Home Manager modules, which a NixOS
    configuration cannot read back — a standalone `userEnvironment`
    attachment is not evaluated during `nixos-rebuild` at all. A plain table
    in the harness layer is therefore the only place both sides can agree on.
  - `webPorts` — the TCP port each browser-serving harness listens on. Same
    table argument as `stateDirs`: the wrapper that binds it and the
    firewall rule that scopes it live on opposite sides of the Home
    Manager/NixOS split, and neither can read the other back.
  - `environmentFor` — environment variables that must hold the *same* value
    on the host and inside the guest, for one home directory.
  - `sandboxWritableRootsFor` — the trees in which harness wrappers may start,
    shared with the host's agent VM declaration so its fixed shares cannot
    drift from the wrappers' admission check.

  - `mkPrompt` — resolves a `(model, variant)` prompt into the three
    depths a harness can inject at (`system`, `preamble`, `context`), from a
    layered `common -> byVariant -> byModel` declaration. See
    its doc comment below for the layer shape. `system` is a `path` (or
    `null`); `preamble` and `context` are single strings — never a list of
    flags — because `--append-system-prompt`-style options do not
    accumulate across repeated invocations.
*/
{
  lib,
  self,
  inputs,
  ...
}:
let
  # Claude Code's own Bash tool exports a `find` shell function into every
  # subprocess it spawns (visible via `declare -f find` inside a session) that
  # redirects to its own `-S dfs`-flagged binary rather than plain findutils
  # — and, empirically, does not itself refuse a literal `/` root. Because
  # bash resolves a function before consulting `PATH`, a PATH-level guard
  # (a `find` package placed ahead of the real one) is shadowed by it and
  # never runs. `BASH_ENV` is bash's own hook for exactly this shape of
  # problem: it names a file every *non-interactive* bash it starts sources
  # first — which is what a harness's Bash tool always is — before running
  # the command, at a point where an inherited exported function already
  # exists and can be captured and wrapped. Whatever `find` a harness already
  # exports (Claude's `bfs` trick, or nothing, as with Codex) is preserved
  # under `_agent_find_upstream` and still runs for any in-tree search; only
  # a root-resolving path is refused. A harness wires this in with
  # `export BASH_ENV=${config}` ahead of its `exec`; it is a no-op for
  # interactive/login shells, which never read `BASH_ENV`.
  findGuardBashEnv =
    pkgs:
    pkgs.writeText "agent-find-guard.bash" ''
      if declare -F find >/dev/null 2>&1; then
        eval "$(declare -f find | sed '1s/^find ()/_agent_find_upstream ()/')"
        # The capture is a textual rewrite of whatever `declare -f find`
        # happened to print; if a future Claude Code build changes that
        # shape enough to break the `sed` pattern, say so on every
        # invocation instead of quietly losing the upstream (`bfs`)
        # implementation to `command find` with no sign anything changed.
        # The root guard below still runs either way.
        declare -F _agent_find_upstream >/dev/null 2>&1 || echo \
          "agent-find-guard: could not capture the exported 'find' function; check tests/agent-find-guard.nix against the new shape" >&2
      fi
      find() {
        local arg path paths=()
        for arg in "$@"; do
          case "$arg" in
            -* | '(' | ')' | '!' | ',') break ;;
            *) paths+=("$arg") ;;
          esac
        done
        (( ''${#paths[@]} == 0 )) && paths=(.)
        if [[ "''${FIND_ALLOW_ROOT:-0}" != 1 ]]; then
          for path in "''${paths[@]}"; do
            if [[ "$(readlink -f -- "$path" 2>/dev/null)" == / ]]; then
              echo "find: refusing to search filesystem root ('$path' -> /); set FIND_ALLOW_ROOT=1 to override" >&2
              return 1
            fi
          done
        fi
        if declare -F _agent_find_upstream >/dev/null 2>&1; then
          _agent_find_upstream "$@"
        else
          command find "$@"
        fi
      }
    '';


  # Leaf artifacts from this author's personal package overlay (`alpkgs`),
  # kept a separate package boundary from the consumer's `pkgs` — same
  # pattern as `preferences/alaestor.nix` and `app-config/mpv.nix`.
  alpkgsFor = pkgs: inputs.alpkgs.packages.${pkgs.stdenv.hostPlatform.system};

  tools =
    pkgs:
    (with pkgs; [
      ripgrep
      git
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
    ])
    ++ (with alpkgsFor pkgs; [
      readability-cli
      archify-cli
    ]);

  toolsMarkdown =
    pkgs:
    lib.concatMapStringsSep "\n" (tool: "- `${builtins.baseNameOf (lib.getExe tool)}`") (tools pkgs);

  fragments = {
    shell = pkgs: ''
      # Shell

      Your shell environment is equipped with the following tools:

      ${toolsMarkdown pkgs}

      Prefer these tools over usual bash alternatives (e.g. rg > grep)

      Run `tldr <program>` to see usage examples.
    '';
    headroom = ''
      ## Headroom shaping

      Multi-line Bash output (e.g. `cat` or `git status --porcelain`) may render condensed, indistinguishable from truncated or wrapped output. Don't re-run the command hoping for improved visibility: if a compression marker prefer `headroom_retrieve` with the hash if a compression marker is visible, otherwise you can do a precise read using a raw `nl -ba <file>`

      You don't need to audit every edit you make unless you have reason to suspect it may have silently failed (e.g. a plausibly indistinct edit in large file, or working with complicated syntax/whitespace).
    '';

    rtk = ''
      ## RTK Rules

      Rust Token Killer reduces CLI context usage in a similar way. It's always safe to use: if rtk has no filter for a command, it passes through unchanged.

      - Always prefix shell commands with rtk, except exact-content reads used to prepare an edit, verify a patch, or when debugging. Those reads must use the raw command to preserve punctuation and whitespace.
      - In command chains, prefix each segment: `rtk git add . && rtk git commit -m "msg"`
      - `rtk proxy <cmd>` runs a command without filtering but tracks usage
    '';

    memory = ''
      # Memory

      Per-project memory index is `.../projects/<project>/memory/MEMORY.md`, along-side the memory files it indexes; its links are relative to that directory.
    '';

    serena = ''
      # Serena — Symbol-First Code Navigation

      Serena's MCP tools expose the project's code symbol graph backed by a
      language server. Prefer these tools over reading whole files: return only
      the code you need, cutting context usage sharply. Read a file end-to-end
      only when the symbol view is insufficient (non-code files, or when you
      need surrounding glue).

      ## Preferred workflow

      - `get_symbols_overview(<file>)` — list a file's top-level symbols before opening it.
      - `find_symbol(<name>)` — fetch a symbol's definition/body instead of reading the file.
      - `find_referencing_symbols(<name>)` — find call sites/usages instead of grepping.
      - `find_declaration(<name>)` — jump to where a symbol is defined.

      ## Rule

      Reach for a symbol tool first; fall back to reading the whole file only when
      the symbol view does not answer the question.
    '';
  };

  # Recursively scans `root` for `SKILL.md`-bearing directories, keyed by
  # their path relative to `root` with `/` flattened to `-`. Moved verbatim
  # (aside from taking `root` as a parameter instead of closing over it)
  # from the identical copies in claude-code.nix and codex.nix.
  collectSkills =
    root:
    let
      go =
        relativeDirectory:
        let
          directory = "${root}${lib.optionalString (relativeDirectory != "") "/${relativeDirectory}"}";
        in
        lib.concatMapAttrs (
          entryName: entryType:
          let
            relativePath = if relativeDirectory == "" then entryName else "${relativeDirectory}/${entryName}";
            entryPath = "${root}/${relativePath}";
          in
          if entryType != "directory" then
            { }
          else if builtins.pathExists "${entryPath}/SKILL.md" then
            { ${builtins.replaceStrings [ "/" ] [ "-" ] relativePath} = entryPath; }
          else
            go relativePath
        ) (builtins.readDir directory);
    in
    go "";

  context = self.data.read "agents/AGENTS.md";

  # Auto-compaction summarizes for narrative continuity and loses the details
  # needed to resume work. This guard replaces it for every harness: one
  # threshold, sitting just under the point a harness would compact on its
  # own, so the agent writes a handoff and further work stops there.
  #
  # It lives here rather than in a harness feature because both sides need the
  # same binary from different module classes -- Claude Code registers it from
  # a Home Manager module, while Codex only honours hooks declared in
  # `/etc/codex/config.toml`, which is NixOS. The harness is selected by
  # `argv[1]`; see the script for what differs between them.
  contextGuard =
    pkgs:
    pkgs.writers.writePython3Bin "agent-context-guard" {
      flakeIgnore = [ "E501" ];
    } (self.data.read "agents/context-guard.py");

  # Codex hook registration. Managed hooks -- those from the system config
  # layer -- are the only ones that run without an interactive `/hooks` trust
  # prompt, and a Nix-managed config is never writable for trust to be
  # recorded into. `[features] hooks` gates managed hooks too, so it must stay
  # enabled in the user config.
  codexHookConfig =
    pkgs:
    let
      guard = "${lib.getExe (contextGuard pkgs)} codex";
      event = name: ''
        [[hooks.${name}]]
        matcher = ""
        [[hooks.${name}.hooks]]
        type = "command"
        command = "${guard}"
      '';
    in
    pkgs.writeText "codex-managed-hooks.toml" ''
      ${event "PostToolUse"}
      ${event "Stop"}
      ${event "SessionStart"}
      ${event "PreCompact"}
    '';

  # Verified against the live system (`ls ~`). Paths are
  # relative to `$HOME`; `stateDirsFor` makes them absolute.
  #
  # These are *live state*, not configuration: sessions, memories, caches,
  # credentials and databases that a harness writes as it runs. The host's
  # Home Manager generation remains the sole manager of the managed files
  # interleaved with them — the guest gets the directory shared read-write
  # and runs no Home Manager of its own, because Home Manager symlinks at
  # file granularity and two generations over one tree rename each other's
  # `settings.json` out of the way.
  harnesses = {
    # `.claude.json` is relocated into `.claude` by this environment value,
    # because virtiofs shares directories rather than individual files.
    claude = {
      stateDirs = [
        ".claude"
        ".cache/claude-cli-nodejs"
      ];
      guestEnvironment = home: {
        CLAUDE_CONFIG_DIR = "${home}/.claude";
      };
    };

    # `.serena-cxs` is Codex's private Serena instance. Codex itself must stay
    # on a guest-local filesystem because its SQLite databases use WAL.
    codex = {
      stateDirs = [ ".serena-cxs" ];
      localStateDirs = [
        {
          directory = ".codex";
          size = 4096;
        }
      ];
    };

    headroom.stateDirs = [ ".headroom" ];
    serena.stateDirs = [ ".serena" ];

    # DSH profiles and plugins must be visible on both sides. Its shipped
    # SQLite query index is in-memory; durable SQLite state would instead
    # require rollback journaling or a guest-local contribution.
    deepseek.stateDirs = [ ".dsh" ];
  };

  vmContributionsFor =
    home: names:
    let
      selected = map (
        name: harnesses.${name} or (throw "unknown agent harness `${name}`")
      ) names;
    in
    {
      stateDirs = map (directory: "${home}/${directory}") (
        lib.concatMap (harness: harness.stateDirs or [ ]) selected
      );
      localStateDirs = map (
        entry: builtins.removeAttrs entry [ "directory" ] // { path = "${home}/${entry.directory}"; }
      ) (lib.concatMap (harness: harness.localStateDirs or [ ]) selected);
      guestEnvironment = lib.foldl' lib.recursiveUpdate { } (
        map (harness: (harness.guestEnvironment or (_: { })) home) selected
      );
    };

  # Compatibility projections for callers that need one contribution class.
  stateDirs = lib.mapAttrs (_: harness: harness.stateDirs or [ ]) harnesses;
  stateDirsFor = home: names: (vmContributionsFor home names).stateDirs;
  localStateDirs = lib.mapAttrs (_: harness: harness.localStateDirs or [ ]) harnesses;
  localStateDirsFor = home: names: (vmContributionsFor home names).localStateDirs;

  # The port table remains separate: it coordinates a Home Manager wrapper and
  # a NixOS firewall rule, rather than contributing guest state.
  webPorts = {
    deepseek = 3080;
  };

  environmentFor = home: (vmContributionsFor home (builtins.attrNames harnesses)).guestEnvironment;

  # The guest home is fresh: only `stateDirs` and the project roots are
  # shared, so `~/.config/git/config` does not exist there and git has no
  # identity at all — `git commit` fails outright, and signing config
  # (`commit.gpgSign`, `user.signingKey`, `gpg.openpgp.program`) is absent
  # even though the gpg-agent channel is available. Pointing
  # `GIT_CONFIG_GLOBAL` at the host's rendered config works because the
  # store is shared into the guest at an identical path, so this costs no
  # new share and copies no state.
  #
  # Harness-agnostic — git identity is not a Claude fact — but derived from
  # a *home* config, which the VM layer (a plain NixOS module) cannot see.
  # It therefore cannot travel through `environmentFor`/`guestEnvironment`
  # and has to be baked into each wrapper, which is why it lives here as a
  # shared fragment rather than in one harness.
  gitConfigGlobalFor =
    homeConfig:
    lib.optionalString homeConfig.programs.git.enable (
      toString homeConfig.xdg.configFile."git/config".source
    );

  gitEnvironmentText =
    homeConfig:
    let
      path = gitConfigGlobalFor homeConfig;
    in
    lib.optionalString (path != "") ''
      export GIT_CONFIG_GLOBAL=${lib.escapeShellArg path}
    '';

  sandboxWritableRootsFor = home: [
    "${home}/Projects"
    "/mnt/Vault/.dotfiles/flake"
  ];

  mkVmSandbox =
    pkgs:
    {
      name,
      native,
      helpFlag ? null,
      herdrAgent ? null,
      forward ? null,
      beforeExec ? "",
    }:
    let
      sandboxWritableRoots = sandboxWritableRootsFor "$HOME";
    in
    ''
      ${lib.optionalString (helpFlag != null) ''
        case "''${1:-}" in
          ${helpFlag})
            exec ${lib.getExe native} "$@"
            ;;
        esac
      ''}

      cwd="$(${pkgs.coreutils}/bin/realpath "$PWD")"
      in_root=0
      sandbox_writable=(
        ${lib.concatMapStringsSep "\n        " (root: ''"${root}"'') sandboxWritableRoots}
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

      ${beforeExec}
      ${lib.optionalString (herdrAgent != null) "export HERDR_AGENT=${lib.escapeShellArg herdrAgent}"}
      exec agent-vm-session \
        ${lib.optionalString (forward != null) "--forward ${lib.escapeShellArg forward} \\"}
        -- bash -c 'cd "$1" && shift && exec "$@"' bash "$cwd" \
        ${lib.getExe native} "$@"
    '';

  # Resolves the text/path a harness injects at each of its three depths
  # (`system`, `preamble`, `context`) for one `(model, variant)`
  # combination. `layers` is:
  #
  #   {
  #     common    = <ops>;                 # applies to every combination
  #     byVariant.<name>  = <ops>;         # applies when variant == <name>
  #     byModel.<name>    = <ops>;         # applies when model == <name>
  #   }
  #
  # `<ops>` is an attrset keyed by depth. For `system` the value is either a
  # `path` (replaces) or `{ replace = path; }`; later layers win. For
  # `preamble` / `context` the value is `{ add = [ ... ]; }` or
  # `{ replace = [ ... ]; }` (discards everything accumulated so far); `add`
  # is shorthand for a plain list. Layers apply in order, later wins for
  # `system`; for `preamble`/`context` the accumulated list is joined with
  # `"\n\n"` at the end — never handed back as a list of flags.
  mkPrompt =
    {
      model,
      variant,
      layers,
    }:
    let
      ops = [
        (layers.common or { })
        (layers.byVariant.${variant} or { })
        (layers.byModel.${model} or { })
      ];

      resolveSystem = lib.foldl' (
        acc: op:
        if !(op ? system) then
          acc
        else if op.system == null then
          null
        else if (builtins.isAttrs op.system) && (op.system ? replace) then
          op.system.replace
        else
          op.system
      ) null ops;

      resolveText =
        depth:
        lib.foldl' (
          acc: op:
          let
            dop = op.${depth} or null;
          in
          if dop == null then
            acc
          else if builtins.isList dop then
            acc ++ dop
          else if dop ? replace then
            dop.replace
          else
            acc ++ (dop.add or [ ])
        ) [ ] ops;
    in
    {
      system = resolveSystem;
      preamble = lib.concatStringsSep "\n\n" (resolveText "preamble");
      context = lib.concatStringsSep "\n\n" (resolveText "context");
    };
in
{
  flake.lib.agents = {
    inherit
      tools
      toolsMarkdown
      fragments
      collectSkills
      context
      contextGuard
      codexHookConfig
      mkPrompt
      harnesses
      vmContributionsFor
      stateDirs
      stateDirsFor
      localStateDirs
      localStateDirsFor
      webPorts
      environmentFor
      gitConfigGlobalFor
      gitEnvironmentText
      sandboxWritableRootsFor
      mkVmSandbox
      findGuardBashEnv
      ;
  };
}
