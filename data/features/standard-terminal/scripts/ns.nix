{
  inputs,
  nixpkgsAllowUnfree,
  pkgs,
  ...
}:
{
  name = "ns";
  enable = true;
  package = pkgs.writeShellApplication {
    name = "ns";
    runtimeInputs = [ pkgs.nix ];
    text = ''
      usage() {
        cat <<'EOF'
Usage: ns <package>...

Opens a shell with the given packages on PATH. A prefix on a package picks
the set it is resolved from; without one, it comes from this flake. Prefixes
are per-package, so one shell can mix sets.

  s.<package>   stable nixpkgs
  u.<package>   unstable nixpkgs
  a.<package>   alpkgs
  <package>     this flake

Every set is pinned by this flake's lock, so a package is the revision the
lock names, not whatever upstream is at right now.

Examples:
  ns u.ripgrep s.python3
  ns a.minilua u.hello
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

      installables=()
      for package; do
        installables+=("$(nix_installable "$package")")
      done

      export NIXPKGS_ALLOW_UNFREE=${nixpkgsAllowUnfree}
      nix shell --impure "''${installables[@]}"
    '';
  };
}
