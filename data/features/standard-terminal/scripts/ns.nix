{
  inputs,
  nixpkgsAllowUnfree,
  pkgs,
}:
pkgs.writeShellApplication {
  name = "ns";
  runtimeInputs = [ pkgs.nix ];
  text = ''
    nix_installable() {
      case "$1" in
        s.*) printf '%s#%s\\n' '${inputs.stable-nixpkgs}' "''${1#s.}" ;;
        u.*) printf '%s#%s\\n' '${inputs.unstable-nixpkgs}' "''${1#u.}" ;;
        *) printf '%s#%s\\n' '${inputs.self}' "$1" ;;
      esac
    }

    installables=()
    for package; do
      installables+=("$(nix_installable "$package")")
    done

    export NIXPKGS_ALLOW_UNFREE=${nixpkgsAllowUnfree}
    nix shell --impure "''${installables[@]}"
  '';
}
