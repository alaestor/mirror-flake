/** Zed editor, enabled by default. */
{
  flake.modules.homeManager.zed =
    { lib, pkgs, ... }:
    {
      programs.zed-editor = {
        enable = lib.mkDefault true;
        defaultEditor = lib.mkDefault false;
        extensions = [
          "nix"
          "log"
          "lua"
          "todo-highlight-language-server"
          "toml"
        ];
        extraPackages = [
          pkgs.nil
          pkgs.lua-language-server
        ];
        userSettings = {
          auto_update = lib.mkDefault false;
          languages.Nix.language_servers = [
            "nil"
            "!nixd"
          ];
          lsp = {
            "lua-language-server".binary.path = lib.mkDefault (lib.getExe pkgs.lua-language-server);
            "package-version-server".binary.path = lib.mkDefault (lib.getExe pkgs.package-version-server);
          };
          semantic_tokens = lib.mkDefault "combined";
          global_lsp_settings.semantic_token_rules = [
            {
              token_type = "todoKeyword";
              foreground_color = "#FF8C00";
              background_color = "#2B1700";
              font_weight = "bold";
            }
            {
              token_type = "fixmeKeyword";
              foreground_color = "#FF2D55";
              background_color = "#2B0011";
              font_weight = "bold";
            }
            {
              token_type = "hackKeyword";
              foreground_color = "#FFD60A";
              background_color = "#272100";
              font_weight = "bold";
            }
            {
              token_type = "noteKeyword";
              foreground_color = "#0A84FF";
              background_color = "#001B2B";
              font_weight = "bold";
            }
            {
              token_type = "infoKeyword";
              foreground_color = "#0A84FF";
              background_color = "#001B2B";
              font_weight = "bold";
            }
            {
              token_type = "warnKeyword";
              foreground_color = "#FF9F0A";
              background_color = "#271B00";
              font_weight = "bold";
            }
            {
              token_type = "warningKeyword";
              foreground_color = "#FF9F0A";
              background_color = "#271B00";
              font_weight = "bold";
            }
            {
              token_type = "bugKeyword";
              foreground_color = "#FF453A";
              background_color = "#2B0A00";
              font_weight = "bold";
            }
            {
              token_type = "xxxKeyword";
              foreground_color = "#BF5AF2";
              background_color = "#1B0029";
              font_weight = "bold";
            }
            {
              token_type = "deprecatedKeyword";
              foreground_color = "#98989D";
              background_color = "#1A1A1A";
              font_weight = "bold";
            }
          ];
          code_lens = lib.mkDefault "on";
          inlay_hints = {
            enabled = lib.mkDefault true;
            show_background = lib.mkDefault true;
          };
          autosave.after_delay.milliseconds = lib.mkDefault 2000;
          calls.mute_on_join = lib.mkDefault true;
          theme = lib.mkDefault "Ayu Dark";
          # Deliberately outside the microVM boundary `docs/agents.md`
          # describes: that boundary is for agentic harnesses run through
          # wrappers (`cc`/`ccs`/`cx`/`cxs`), where reducing blast radius is
          # the point. Zed runs natively on the host with a GUI and a human
          # driving it, which is a different trust model with its own
          # mitigations (interactive review, no unattended sessions) rather
          # than the VM's isolation guarantee.
          session.trust_all_worktrees = lib.mkDefault true;
          telemetry = {
            diagnostics = lib.mkDefault false;
            metrics = lib.mkDefault false;
          };
          diagnostics.inline.enabled = lib.mkDefault true;
          relative_line_numbers = lib.mkDefault "enabled";
          vim_mode = lib.mkDefault true;
          vim.toggle_relative_line_numbers = lib.mkDefault true;
          search.regex = lib.mkDefault true;
          ui_font_size = lib.mkDefault 16;
          buffer_font_size = lib.mkDefault 16;
        };
      };
    };
}
