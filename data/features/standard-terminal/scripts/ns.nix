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
      nix_installable() {
        case "$1" in
          s.*) printf '%s#%s' '${inputs.stable-nixpkgs}' "''${1#s.}" ;;
          u.*) printf '%s#%s' '${inputs.unstable-nixpkgs}' "''${1#u.}" ;;
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
