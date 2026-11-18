/**
  Implements the interactive terminal feature and packages every direct
  `data/features/standard-terminal/scripts/*.nix` declaration. Each script
  file must return a script declaration whose name and package name match its
  filename. Declarations can disable themselves from their supplied context.

  `flake.modules.homeManager.standard-terminal-tailnet` is the dormant option
  interface declaring `standard-terminal.tailscale.domain`; the Tailscale
  feature imports it to supply the suffix. The Nix-on-Droid adapter shares the
  terminal programs and Nushell configuration, but omits Ghostty.
  Bash and Nushell functions adapt the external ncd helper so it can change
  the current shell's directory to the cached local flake root.
  `nwhere` prints that cached flake reference without fetching or changing it.
  `hbuild` uses the same cached target and --flake override as `hswitch`.
  `nup` updates the cached flake, automatically repairing and verifying the
  Caddy plugin source hash for local checkouts containing its source manifest.
  `nup-refresh-caddy` performs only that repair from the current flake root.
  `pw` generates Diceware passphrases in any shell, defaulting to 4 to 7 words
  joined by underscores and a random number of fully uppercased words.
  --words, --caps, and --sep override those defaults. Random choices use the
  operating system's random source, including word positions to uppercase.
  `lsblkrm` lists removable block devices as a table, or preserves lsblk's
  JSON structure with --json for structured consumers. A thin Nushell adapter
  returns device records so its existing pipelines and table display work.
  `ngc` previews profile pruning and requires confirmation before store GC.
  It retains generations newer than `--older-than 14d`, the newest
  `--keep-last 5` per profile, and the selected generation. NixOS runs it
  through sudo; Droid runs it without elevation. It inspects standard system,
  per-user, and XDG profile directories, including the caller's XDG_STATE_HOME.
  `--clean-roots` also unregisters aged build-result and direnv roots, leaving
  project symlinks and manual roots alone. Store GC itself is not age-limited.
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
            fetchPrograms = if includePrograms then {
              inherit (config.programs) fastfetch hyfetch;
            } else null;
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
        includePrograms = true;
        isNixOnDroid = true;
      })
    ];
  };
}
