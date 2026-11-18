{ pkgs, ... }:
{
  name = "lsblkrm";
  enable = true;
  package = pkgs.writeShellApplication {
    name = "lsblkrm";
    runtimeInputs = [ pkgs.util-linux pkgs.jq ];
    text = ''
      usage() { printf 'Usage: lsblkrm [--json]\n'; }
      format=table
      if [ "$#" -gt 0 ]; then
        [ "$#" -eq 1 ] || { usage >&2; exit 2; }
        case "$1" in
          --json) format=json ;;
          -h|--help) usage; exit 0 ;;
          *) usage >&2; exit 2 ;;
        esac
      fi
      devices=$(lsblk -d -l -o NAME,SIZE,MODEL,TRAN,RM,RO --json | jq '
        .blockdevices |= map(select(.rm == true))
      ')
      if [ "$format" = json ]; then
        printf '%s\n' "$devices"
      else
        printf '%s\n' "$devices" | jq -r '
          ["NAME", "SIZE", "MODEL", "TRAN", "RM", "RO"],
          (.blockdevices[] | [.name, .size, .model, .tran, .rm, .ro])
          | @tsv
        ' | column -t -s $'\t'
      fi
    '';
  };
}
