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
      if [ "$#" -lt 1 ]; then
        printf 'Usage: nr <package> [arguments...]\\n' >&2
        exit 2
      fi

      nix_installable() {
        case "$1" in
          s.*) printf '%s#%s\\n' '${inputs.stable-nixpkgs}' "''${1#s.}" ;;
          u.*) printf '%s#%s\\n' '${inputs.unstable-nixpkgs}' "''${1#u.}" ;;
          *) printf '%s#%s\\n' '${inputs.self}' "$1" ;;
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
