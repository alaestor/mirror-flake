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

        - When running shell commands, **always prefix with `rtk`**
        - In command chains, prefix each segment: `rtk git add . && rtk git commit -m "msg"`
        - For debugging, use the raw command without an rtk prefix
        - `rtk proxy <cmd>` runs a command without filtering but tracks usage
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
            headroom_args=(
              --code-memory ${if withSerena then "serena" else "none"}
              --tool-search true
              ${lib.optionalString withSerena "--serena-instructions"}
            )
            claude_args=()

            while (( $# )); do
              case "$1" in
                sonnet|opus|haiku) model="$1" ;;
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
                --cc-help)
                  echo "usage: ${name} [sonnet|opus|haiku] [lo|med|hi|max] [user|edits|auto|plan|bypass] [memory|graph|1m|search] [--] [claude arguments...]"
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
            claude_args+=( --append-system-prompt ${lib.escapeShellArg shellInstructions} )

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
