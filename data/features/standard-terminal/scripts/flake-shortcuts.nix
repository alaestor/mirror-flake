{
  isNixOnDroid,
  pkgs,
  ...
}:
let
  backend = pkgs.writeShellApplication {
    name = "nflake-target";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      state_file() {
        if [ -n "''${XDG_STATE_HOME:-}" ]; then
          printf '%s/nix-flake-shortcuts/target\n' "$XDG_STATE_HOME"
        elif [ -n "''${HOME:-}" ]; then
          printf '%s/.local/state/nix-flake-shortcuts/target\n' "$HOME"
        else
          printf 'nflake-target: neither XDG_STATE_HOME nor HOME is set\n' >&2
          return 1
        fi
      }

      read_target() {
        local file target
        file=$(state_file) || return
        if [ ! -r "$file" ]; then
          printf 'nflake-target: no flake target is cached; pass --flake <reference> to a shortcut first\n' >&2
          return 1
        fi
        IFS= read -r target < "$file" || [ -n "$target" ]
        if [ -z "$target" ]; then
          printf 'nflake-target: cached flake target is empty: %s\n' "$file" >&2
          return 1
        fi
        printf '%s\n' "$target"
      }

      normalize_target() {
        local target="$1" base fragment="" path prefix="" resolved
        base="''${target%%#*}"
        if [ "$base" != "$target" ]; then
          fragment="#''${target#*#}"
        fi

        case "$base" in
          path:*)
            prefix="path:"
            path="''${base#path:}"
            ;;
          *) path="$base" ;;
        esac

        if [ -d "$path" ]; then
          resolved=$(cd -- "$path" && pwd -P)
          printf '%s%s%s\n' "$prefix" "$resolved" "$fragment"
        else
          printf '%s\n' "$target"
        fi
      }

      remember_target() {
        local target file directory temporary
        target=$(normalize_target "$1") || return
        file=$(state_file) || return
        directory="''${file%/*}"
        umask 077
        mkdir -p -- "$directory"
        temporary=$(mktemp "$directory/.target.XXXXXX")
        printf '%s\n' "$target" > "$temporary"
        mv -f -- "$temporary" "$file"
      }

      local_path() {
        local target base path
        target=$(read_target) || return
        base="''${target%%#*}"
        case "$base" in
          path:*) path="''${base#path:}" ;;
          *:*)
            printf 'ncd: cached flake target is not a local path: %s\n' "$target" >&2
            return 1
            ;;
          *) path="$base" ;;
        esac

        if [ ! -d "$path" ]; then
          printf 'ncd: cached flake directory does not exist: %s\n' "$path" >&2
          return 1
        fi
        if [ ! -f "$path/flake.nix" ]; then
          printf 'ncd: cached target is not a flake root: %s\n' "$path" >&2
          return 1
        fi
        cd -- "$path"
        pwd -P
      }

      run_shortcut() {
        local shortcut="$1" explicit_target="" target status
        local -a forwarded command
        shift
        forwarded=("$@")

        while [ "$#" -gt 0 ]; do
          case "$1" in
            --flake)
              if [ "$#" -lt 2 ]; then
                break
              fi
              explicit_target="$2"
              shift 2
              ;;
            --flake=*)
              explicit_target="''${1#--flake=}"
              shift
              ;;
            *) shift ;;
          esac
        done

        if [ -z "$explicit_target" ]; then
          target=$(read_target) || return
          forwarded+=(--flake "$target")
        fi

        case "$shortcut" in
          nswitch)
            ${if isNixOnDroid then ''command=(nix-on-droid switch)'' else ''command=(sudo nixos-rebuild switch)''}
            ;;
          nboot)
            ${if isNixOnDroid then ''printf 'nboot: nix-on-droid has no boot action\n' >&2; return 2'' else ''command=(sudo nixos-rebuild boot)''}
            ;;
          ndry)
            ${if isNixOnDroid then ''printf 'ndry: nix-on-droid has no dry-build action\n' >&2; return 2'' else ''command=(nixos-rebuild dry-build)''}
            ;;
          ntest)
            ${if isNixOnDroid then ''printf 'ntest: nix-on-droid has no test action\n' >&2; return 2'' else ''command=(nixos-rebuild test)''}
            ;;
          hswitch) command=(home-manager switch) ;;
          *)
            printf 'nflake-target: unknown shortcut: %s\n' "$shortcut" >&2
            return 2
            ;;
        esac

        if "''${command[@]}" "''${forwarded[@]}"; then
          if [ -n "$explicit_target" ]; then
            remember_target "$explicit_target"
          fi
        else
          status=$?
          return "$status"
        fi
      }

      case "''${1:-}" in
        local-path)
          [ "$#" -eq 1 ] || {
            printf 'Usage: nflake-target local-path\n' >&2
            exit 2
          }
          local_path
          ;;
        run)
          [ "$#" -ge 2 ] || {
            printf 'Usage: nflake-target run <shortcut> [arguments...]\n' >&2
            exit 2
          }
          shift
          run_shortcut "$@"
          ;;
        *)
          printf 'Usage: nflake-target {local-path|run <shortcut> [arguments...]}\n' >&2
          exit 2
          ;;
      esac
    '';
  };

  mkShortcut = name: pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = [ backend ];
    text = ''
      exec nflake-target run ${name} "$@"
    '';
  };

  ncd = pkgs.writeShellApplication {
    name = "ncd";
    runtimeInputs = [ backend ];
    text = ''
      exec nflake-target local-path "$@"
    '';
  };
in
{
  name = "flake-shortcuts";
  enable = true;
  package = pkgs.symlinkJoin {
    name = "flake-shortcuts";
    paths = [
      backend
      ncd
      (mkShortcut "hswitch")
      (mkShortcut "nboot")
      (mkShortcut "ndry")
      (mkShortcut "nswitch")
      (mkShortcut "ntest")
    ];
  };
}
