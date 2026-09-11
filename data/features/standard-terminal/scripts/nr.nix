{
  inputs,
  nixpkgsAllowUnfree,
  pkgs,
  ...
}:
{
  name = "nr";
  enable = true;
  package = pkgs.writeShellApplication {
    name = "nr";
    runtimeInputs = [ pkgs.nix ];
    text = ''
      usage() {
        cat <<'EOF'
Usage: nr <package> [arguments...]

Runs a package without installing it. A prefix on <package> picks the set
it is resolved from; without one, it comes from this flake.

  s.<package>   stable nixpkgs
  u.<package>   unstable nixpkgs
  a.<package>   alpkgs
  <package>     this flake

Every set is pinned by this flake's lock, so a package is the revision the
lock names, not whatever upstream is at right now.

Examples:
  nr u.ffmpeg -i in.mkv out.mp4
  nr a.minilua --help
EOF
      }

      if [ "$#" -lt 1 ]; then
        usage >&2
        exit 2
      fi

      case "$1" in
        -h | --help) usage; exit 0 ;;
      esac

      nix_installable() {
        case "$1" in
          s.*) printf '%s#%s' '${inputs.stable-nixpkgs}' "''${1#s.}" ;;
          u.*) printf '%s#%s' '${inputs.unstable-nixpkgs}' "''${1#u.}" ;;
          a.*) printf '%s#%s' '${inputs.alpkgs}' "''${1#a.}" ;;
          *) printf '%s#%s' '${inputs.self}' "$1" ;;
        esac
      }

      installable=$(nix_installable "$1")
      shift

      export NIXPKGS_ALLOW_UNFREE=${nixpkgsAllowUnfree}
      if [ "$#" -eq 0 ]; then
        nix run --impure "$installable"
      else
        nix run --impure "$installable" -- "$@"
      fi
    '';
  };
}
