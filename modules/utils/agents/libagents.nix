/**
  # flake.lib.agents

  Shared definitions consumed by every harness feature module
  (`modules/features/claude-code.nix`, `modules/features/codex.nix`, and any
  future addition). This is the harness *layer*: it knows about tool lists,
  prompt fragments, skills and `AGENTS.md`. It must never mention vsock,
  virtiofs, systemd units, or anything belonging to the VM layer
  (`modules/utils/agents/vm.nix`) — see the layering picture in
  `__reference/implementation-guide-agent-microvms.md`.

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
  tools =
    pkgs: with pkgs; [
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
      ;
  };
}
