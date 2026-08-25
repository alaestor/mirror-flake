{
  flake.modules.homeManager.git =
    { lib, ... }:
    {
      programs.git = {
        enable = lib.mkDefault true;
        lfs = {
          enable = lib.mkDefault true;
          skipSmudge = lib.mkDefault true;
        };
        ignores = [
          "__*"
          ".zed/"
          "*.bak"
          "*.old"
          "*.kate-swp"
          "*.ignore"
          "*~"
          ".*.swp"
        ];
        settings = {
          init.defaultBranch = lib.mkDefault "main";
          # `log.abbrevCommit` is a boolean (whether to abbreviate at all);
          # the intent here was full 40-character hashes, which is
          # `core.abbrev`, not a truthy string coerced into that boolean.
          core.abbrev = lib.mkDefault 40;
          column.ui = lib.mkDefault "auto";
          branch.sort = lib.mkDefault "-committerdate";
          tag.sort = lib.mkDefault "version:refname";
          diff = {
            algorithm = lib.mkDefault "histogram";
            colorMoved = lib.mkDefault "plain";
            mnemonicPrefix = lib.mkDefault true;
            renames = lib.mkDefault true;
          };
          push = {
            default = lib.mkDefault "simple";
            autoSetupRemote = lib.mkDefault true;
            followTags = lib.mkDefault true;
          };
          fetch = {
            prune = lib.mkDefault true;
            pruneTags = lib.mkDefault true;
            all = lib.mkDefault true;
          };
          help.autocorrect = lib.mkDefault "prompt";
          commit.verbose = lib.mkDefault true;
          rerere = {
            enabled = lib.mkDefault true;
            autoupdate = lib.mkDefault true;
          };
          merge.conflictStyle = lib.mkDefault "zdiff3";
        };
      };

      programs.nushell.shellAliases = {
        lola = lib.mkDefault "git log --graph --decorate --pretty=oneline --abbrev-commit --all";
        lolno = lib.mkDefault "git reset --mixed HEAD~1";
      };
    };
}
