/**
  Implements the interactive terminal feature and packages every direct
  `data/features/standard-terminal/scripts/*.nix` declaration. Each script
  file must return a script declaration whose name and package name match its
  filename. Declarations can disable themselves from their supplied context.

  # TODO(workaround): try nushell config with newer pinnned nixpkgs
  `flake.modules.homeManager.standard-terminal-tailnet` is the dormant option
  interface declaring `standard-terminal.tailscale.domain`; the Tailscale
  feature imports it to supply the suffix. The Nix-on-Droid adapter provides Nushell and these script packages, but
  omits other program integrations unavailable from its pinned Home Manager.
  Bash and Nushell functions adapt the external ncd helper so it can change
  the current shell's directory to the cached local flake root.
*/
{ inputs, self, ... }:
let
  mkHomeModule =
    {
      includeGhostty,
      includePrograms,
      isNixOnDroid,
    }:
    { config, lib, pkgs, ... }:
    let

      # automatic discovery of scripts
      nixpkgsAllowUnfree = if pkgs.config.allowUnfree or false then "1" else "0";
      scriptDirectory = self.data.path "features/standard-terminal/scripts";
      scriptPackages = lib.filter (script: script.enable) (lib.mapAttrsToList (
        fileName: _:
        let
          expectedName = lib.removeSuffix ".nix" fileName;
          script = import "${scriptDirectory}/${fileName}" {
            inherit inputs nixpkgsAllowUnfree pkgs;
            inherit isNixOnDroid;
            tailnetDomain = config.standard-terminal.tailscale.domain;
          };
        in
        if script.name != expectedName || script.package.name != expectedName then
          throw "standard-terminal script ${fileName} declares the mismatched name ${script.name}"
        else
          script
      ) (lib.filterAttrs (fileName: fileType: fileType == "regular" && lib.hasSuffix ".nix" fileName) (
        builtins.readDir scriptDirectory
      )));

      # processed "uwu" themed fastfetch config (inserts ascii art)
      customLogoPath = self.data.vars.textart.boykisser;
      fastfetchUwuSettingsPath = pkgs.writeText "fastfetch-uwu.json" (
        builtins.replaceStrings [ "__NIX_REPLACED_LOGO_PATH__" ] [ (toString customLogoPath) ] (
          self.data.read "features/standard-terminal/fastfetch_uwu.json"
        )
      );

    in
    {
      imports = with inputs.self.modules.homeManager;
        [ standard-terminal-tailnet ]
        ++ lib.optional includePrograms nushell
        ++ lib.optional includeGhostty ghostty;

      config = {
        home.packages = map (script: script.package) scriptPackages;
        programs = lib.mkMerge [
          {
            # TODO: normalize the ncd/nboot/hswitch commands into focused features.
            bash = {
              enable = lib.mkDefault true;
              initExtra = lib.mkAfter ''
                ncd() {
                  local target
                  target="$(command ncd)" || return
                  builtin cd -- "$target"
                }

                # Refuse `find` invocations whose search root resolves to `/`,
                # since a runaway system-wide scan (e.g. an agent typo) is
                # slow and unhelpful. `FIND_ALLOW_ROOT=1 find ...` bypasses it.
                find() {
                  local arg path paths=()
                  for arg in "$@"; do
                    case "$arg" in
                      -* | '(' | ')' | '!' | ',') break ;;
                      *) paths+=("$arg") ;;
                    esac
                  done
                  ((''${#paths[@]} == 0)) && paths=(.)
                  if [[ "''${FIND_ALLOW_ROOT:-0}" != 1 ]]; then
                    for path in "''${paths[@]}"; do
                      if [[ "$(readlink -f -- "$path" 2>/dev/null)" == / ]]; then
                        echo "find: refusing to search filesystem root ('$path' -> /); set FIND_ALLOW_ROOT=1 to override" >&2
                        return 1
                      fi
                    done
                  fi
                  command find "$@"
                }
              '';
            };
            nushell.extraConfig = lib.mkAfter ''
              def --env ncd [] {
                let target = (^ncd)
                if $env.LAST_EXIT_CODE == 0 {
                  cd $target
                }
              }
            '';
          }
          (lib.optionalAttrs includePrograms (
            (lib.optionalAttrs includeGhostty {
              ghostty.settings = {
                command = lib.mkDefault "nu";
                working-directory = lib.mkDefault config.home.homeDirectory;
              };
            })
            // {
              fastfetch = {
                enable = lib.mkDefault true;
                settings = self.data.readJSON "features/standard-terminal/fastfetch.json";
              };

              hyfetch = {
                enable = lib.mkDefault true;
                settings = {
                  backend = lib.mkDefault "fastfetch";
                  mode = lib.mkDefault "rgb";
                  preset = lib.mkDefault "random";
                  light_dark = lib.mkDefault "dark";
                  pride_month_disable = lib.mkDefault true;
                  color_align.mode = lib.mkDefault "horizontal";
                };
              };

              carapace = {
                enable = lib.mkDefault true;
                enableNushellIntegration = lib.mkDefault true;
              };

              starship = {
                enable = lib.mkDefault true;
                enableNushellIntegration = lib.mkDefault true;
                enableBashIntegration = lib.mkDefault false;
                settings = {
                  add_newline = lib.mkDefault true;
                  character = {
                    success_symbol = lib.mkDefault "[λ](bold green)";
                    error_symbol = lib.mkDefault "[✗](bold red)";
                  };
                };
              };

              zoxide = {
                enable = lib.mkDefault true;
                enableNushellIntegration = lib.mkDefault true;
              };

              atuin = {
                enable = lib.mkDefault true;
                enableNushellIntegration = lib.mkDefault true;
              };

              nushell.extraConfig = lib.mkAfter ''
                def --wrapped ff [...args] {
                  fastfetch ...$args
                }

                def --wrapped ffuwu [...args] {
                  fastfetch -c ${fastfetchUwuSettingsPath} ...$args
                }

                def --wrapped hy [...args] {
                  hyfetch ...$args
                }

                def --wrapped hyuwu [...args] {
                  hyfetch --ascii-file ${customLogoPath} ...$args --args "-c ${fastfetchUwuSettingsPath}"
                }

                if $nu.is-interactive {
                  clear
                }
              '';
            }
          ))
        ];
      };
    };
in
{
  flake.modules.homeManager.standard-terminal-tailnet = { lib, ... }: {
    # The interface may arrive through both standard-terminal and a contributing feature.
    key = "flake.modules.homeManager.standard-terminal-tailnet";

    options.standard-terminal.tailscale.domain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Tailnet DNS suffix that enables the ts SSH shortcut.";
    };
  };

  flake.modules.homeManager.standard-terminal = mkHomeModule {
    includeGhostty = true;
    includePrograms = true;
    isNixOnDroid = false;
  };

  flake.modules.nixOnDroid.standard-terminal = {
    userEnvironment.sharedModules = [
      (mkHomeModule {
        includeGhostty = false;
        includePrograms = false;
        isNixOnDroid = true;
      })
      { programs.nushell.enable = true; }
    ];
  };
}
