{ inputs, ... }:
{
  flake.modules.homeManager.ai-coding =
    { pkgs, ... }:
    let
      preferredModel = "qwen/qwen3.6-27b";
      preferred = {
        provider = "lmstudio";
        model = preferredModel;
      };
      favorites = {
        local.lmstudio = [
          {
            provider = "lmstudio";
            model = "google/gemma-4-31b-qat";
            enable_thinking = false;
          }
          {
            provider = "lmstudio";
            model = "google/gemma-4-26b-a4b-qat";
            enable_thinking = false;
          }
          {
            provider = "lmstudio";
            model = preferredModel;
            enable_thinking = false;
          }
        ];
        openrouter = [
          {
            provider = "openrouter";
            model = "deepseek/deepseek-v4-flash";
            enable_thinking = true;
          }
          {
            provider = "openrouter";
            model = "minimax/minimax-m3";
            enable_thinking = true;
          }
          {
            provider = "openrouter";
            model = "deepseek/deepseek-v4-pro";
            enable_thinking = true;
          }
          {
            provider = "openrouter";
            model = "x-ai/grok-4.5";
            enable_thinking = true;
          }
          {
            provider = "openrouter";
            model = "openai/gpt-5.6-terra";
            enable_thinking = true;
          }
          {
            provider = "openrouter";
            model = "openai/gpt-5.6-luna";
            enable_thinking = true;
          }
          {
            provider = "openrouter";
            model = "openai/gpt-5.6-sol";
            enable_thinking = true;
          }
          {
            provider = "openrouter";
            model = "qwen/qwen3.7-plus";
            enable_thinking = true;
          }
          {
            provider = "openrouter";
            model = "qwen/qwen3.5-flash-02-23";
            enable_thinking = true;
          }
        ];
        subs.openai = [
          {
            provider = "openai-subscribed";
            model = "gpt-5.5";
            enable_thinking = true;
            effort = "medium";
          }
          {
            provider = "openai-subscribed";
            model = "gpt-5.4-mini";
            enable_thinking = true;
            effort = "medium";
          }
        ];
      };
      flattenLists =
        value:
        if builtins.isList value then
          value
        else if builtins.isAttrs value then
          builtins.concatLists (builtins.map flattenLists (builtins.attrValues value))
        else
          [ ];
      favoriteModels = flattenLists favorites;
    in
    {
      imports = with inputs.self.modules.homeManager; [
        claude-code
        codex
        zed
        agents-prompt-preview
      ];

      home.packages = [
        pkgs.lmstudio
        pkgs.herdr
      ];

      programs.zed-editor.userSettings = {
        agent = {
          favorite_models = favoriteModels;
          default_profile = "ask";
          default_model = preferred;
          enable_feedback = false;
          show_turn_stats = true;
          thinking_display = "preview";
          tool_permissions.tools = {
            delete_path.default = "allow";
            move_path.default = "allow";
            create_directory.default = "allow";
            terminal.always_allow = [
              { pattern = "^nix\\s+build(\\s|$)"; }
              { pattern = "^nix\\s+flake(\\s|$)"; }
            ];
          };
        };
        language_models.lmstudio.api_url = "http://127.0.0.1:1234/api/v0";
        edit_predictions = {
          provider = "open_ai_compatible_api";
          open_ai_compatible_api = {
            max_output_tokens = 256;
            model = preferredModel;
            api_url = "http://localhost:1234";
          };
          allow_data_collection = "no";
        };
      };
    };
}
