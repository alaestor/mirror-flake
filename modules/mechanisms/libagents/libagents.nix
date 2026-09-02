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
    from naming any of them (`implementation-guide.md` Phase 6) and the
    harness modules themselves are Home Manager modules, which a NixOS
    configuration cannot read back — a standalone `userEnvironment`
    attachment is not evaluated during `nixos-rebuild` at all. A plain table
    in the harness layer is therefore the only place both sides can agree on.
  - `environmentFor` — environment variables that must hold the *same* value
    on the host and inside the guest, for one home directory.

  - `mkPrompt` — resolves a `(harness, model, variant)` prompt into the three
    depths a harness can inject at (`system`, `preamble`, `context`), from a
    layered `common -> byHarness -> byVariant -> byModel` declaration. See
    its doc comment below for the layer shape. `system` is a `path` (or
    `null`); `preamble` and `context` are single strings — never a list of
    flags — because `--append-system-prompt`-style options do not
    accumulate across repeated invocations.
*/
{ lib, self, ... }:
let
  # Claude Code's own Bash tool exports a `find` shell function into every
  # subprocess it spawns (visible via `declare -f find` inside a session) that
  # redirects to its own `-S dfs`-flagged binary rather than plain findutils
  # — and, empirically, does not itself refuse a literal `/` root. Because
  # bash resolves a function before consulting `PATH`, `findGuard` below
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

  # A harness's Bash tool runs non-interactive subshells that never source
  # `~/.bashrc` (`modules/features/standard-terminal.nix`'s `find` guard is
  # therefore invisible to it), so the same guard has to exist as an actual
  # `find` binary placed ahead of the real one on `PATH` — every
  # `mkHarnessWrappers` call prepends `runtimeInputs` (and therefore `tools`)
  # via `writeShellApplication`'s wrapper, so this shadows
  # `pkgs.findutils`'s `find` for every harness built from `tools` below. It
  # is only reached when nothing has already claimed the `find` function name
  # (`findGuardBashEnv` above covers that case) — kept anyway as a backstop
  # for a harness that execs `find` without going through such a function.
  # Delegates to the real binary by absolute store path, not by name, so
  # `command find`/`exec find` inside here cannot recurse back into itself.
  findGuard =
    pkgs:
    pkgs.writeShellScriptBin "find" ''
      paths=()
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
            exit 1
          fi
        done
      fi
      exec ${pkgs.findutils}/bin/find "$@"
    '';

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
    ++ [ (findGuard pkgs) ];

  toolsMarkdown =
    pkgs:
    lib.concatMapStringsSep "\n" (tool: "- `${builtins.baseNameOf (lib.getExe tool)}`") (tools pkgs);

  fragments = {
    shell = pkgs: ''
      # Shell

      Your shell environment is equipped with the following tools:

      ${toolsMarkdown pkgs}

      Run `tldr <program>` to see usage examples.
    '';

    # Prose taken verbatim from claude-code.nix, the newer and more complete
    # of the two copies that had drifted between claude-code.nix and
    # codex.nix. Codex previously lacked this paragraph entirely; folding it
    # in here is the one intentional behaviour change in this move.
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

  # Verified against the live system (`ls ~`) rather than copied from the
  # guide's table, which the guide itself says to distrust. Paths are
  # relative to `$HOME`; `stateDirsFor` makes them absolute.
  #
  # These are *live state*, not configuration: sessions, memories, caches,
  # credentials and databases that a harness writes as it runs. The host's
  # Home Manager generation remains the sole manager of the managed files
  # interleaved with them — the guest gets the directory shared read-write
  # and runs no Home Manager of its own, because Home Manager symlinks at
  # file granularity and two generations over one tree rename each other's
  # `settings.json` out of the way (`implementation-guide.md` Phase 6,
  # "the ownership rule").
  stateDirs = {
    # `.claude.json` lives at the top of `$HOME` by default and virtiofs
    # shares directories, not files. `CLAUDE_CONFIG_DIR` (see
    # `environmentFor`) relocates it into the config directory, so sharing
    # `.claude` is enough to carry it too.
    claude = [
      ".claude"
      ".cache/claude-cli-nodejs"
    ];
    # `.serena-cxs` is codex's own serena instance, pinned there by
    # `SERENA_HOME` in `modules/features/codex.nix`; it belongs to codex
    # rather than to the shared serena component below.
    codex = [
      ".codex"
      ".serena-cxs"
    ];
    headroom = [ ".headroom" ];
    # serena's default `SERENA_HOME`, which is what headroom's
    # `--code-memory serena` (the `ccs` wrapper) ends up using.
    serena = [ ".serena" ];
  };

  stateDirsFor =
    home: names:
    map (directory: "${home}/${directory}") (lib.concatMap (name: stateDirs.${name}) names);

  # Set on the host *and* in the guest, to the same value, or the two
  # disagree about where state lives and each writes a config the other
  # never reads. Consumed by the harness's Home Manager module on the host
  # and handed to the VM as opaque `name = value` pairs on the guest side,
  # so the VM layer still never learns what `.claude` is.
  environmentFor = home: {
    CLAUDE_CONFIG_DIR = "${home}/.claude";
  };

  # Resolves the text/path a harness injects at each of its three depths
  # (`system`, `preamble`, `context`) for one `(harness, model, variant)`
  # combination. `layers` is:
  #
  #   {
  #     common    = <ops>;                 # applies to every combination
  #     byHarness.<name>  = <ops>;         # applies when harness == <name>
  #     byVariant.<name>  = <ops>;         # applies when variant == <name>
  #     byModel.<name>    = <ops>;         # applies when model == <name>
  #   }
  #
  # `<ops>` is an attrset keyed by depth. For `system` the value is either a
  # `path` (replaces) or `{ replace = path; }`; later layers win. For
  # `preamble` / `context` the value is `{ add = [ ... ]; }`,
  # `{ drop = [ ... ]; }` (removes matching items already accumulated), or
  # `{ replace = [ ... ]; }` (discards everything accumulated so far); `add`
  # is shorthand for a plain list. Layers apply in order, later wins for
  # `system`; for `preamble`/`context` the accumulated list is joined with
  # `"\n\n"` at the end — never handed back as a list of flags.
  mkPrompt =
    {
      pkgs ? null,
      harness,
      model,
      variant,
      layers,
    }:
    let
      ops = [
        (layers.common or { })
        (layers.byHarness.${harness} or { })
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
            let
              added = dop.add or [ ];
              dropped = dop.drop or [ ];
              kept = lib.filter (item: !(builtins.elem item dropped)) acc;
            in
            kept ++ added
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
      mkPrompt
      stateDirs
      stateDirsFor
      environmentFor
      findGuardBashEnv
      ;
  };
}
