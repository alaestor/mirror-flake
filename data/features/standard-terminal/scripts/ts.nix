{
  pkgs,
  tailnetDomain,
  ...
}:
{
  name = "ts";
  enable = tailnetDomain != null;
  package = pkgs.writeShellApplication {
    name = "ts";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      if [ "$#" -lt 1 ]; then
        printf 'Usage: ts [user@]host [ssh arguments...]\\n' >&2
        exit 2
      fi

      target="$1"
      shift
      exec ssh "$target.${tailnetDomain}" "$@"
    '';
  };
}
