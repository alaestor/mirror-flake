{ inputs, pkgs, system }:
let
  lib = pkgs.lib;
  droid = lib.evalModules {
    modules = [
      inputs.self.modules.nixOnDroid.standard-terminal
      {
        options.userEnvironment.sharedModules = lib.mkOption {
          type = lib.types.listOf lib.types.deferredModule;
          default = [ ];
        };
      }
    ];
  };
  evaluate = homeManager: packages: modules: homeManager.lib.homeManagerConfiguration {
    pkgs = packages;
    inherit modules;
  };
  identity = {
    home.username = "terminal-fixture";
    home.homeDirectory = "/tmp/terminal-fixture";
    home.stateVersion = "24.11";
    home.sessionVariables.TERMINAL_FIXTURE = "loaded";
  };
  android = evaluate inputs.android-home-manager
    (import inputs.android-nixpkgs { inherit system; })
    (droid.config.userEnvironment.sharedModules ++ [ identity ]);
  desktop = evaluate inputs.unstable-home-manager pkgs [
    inputs.self.modules.homeManager.standard-terminal
    identity
  ];
  programs = [ "nushell" "fastfetch" "hyfetch" "carapace" "starship" "zoxide" "atuin" ];
  enabled = config: lib.all (name: config.programs.${name}.enable) programs;
  androidConfig = android.config;
  desktopConfig = desktop.config;
in
assert lib.assertMsg (enabled androidConfig && enabled desktopConfig)
  "standard-terminal must enable its shared terminal programs on desktop and Droid";
assert lib.assertMsg (!androidConfig.programs.ghostty.enable && desktopConfig.programs.ghostty.enable)
  "standard-terminal must omit Ghostty only on Droid";
assert lib.assertMsg (androidConfig.programs.nushell.settings.show_banner == false)
  "Droid must receive the shared Nushell configuration";
assert lib.assertMsg desktopConfig.programs.nushell.loadSessionVariables
  "desktop must retain Nushell session-variable loading";
pkgs.runCommand "standard-terminal-test" {
  nativeBuildInputs = [ androidConfig.programs.nushell.package ];
  configFile = androidConfig.home.file."/tmp/terminal-fixture/.config/nushell/config.nu".source;
} ''
  export XDG_CONFIG_HOME="$TMPDIR/config"
  export XDG_CACHE_HOME="$TMPDIR/cache"
  export XDG_DATA_HOME="$TMPDIR/data"
  mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"
  nu --config "$configFile" --no-history -c '
    if $env.config.show_banner { error make {msg: "shared Nushell settings missing"} }
    if (which ncd | is-empty) { error make {msg: "ncd missing"} }
    if $env.TERMINAL_FIXTURE != "loaded" { error make {msg: "session variables missing"} }
  '
  touch "$out"
''
