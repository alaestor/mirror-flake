{ context }:
with context;
{
  name = "timestamped_now";
  description = "Return a new timestamped path.";
  category = "internal";
  wrapped = false;
  hidden = true;
  content = ''
    set -euo pipefail
    path="$1"
    dir=$(dirname "$path")
    base=$(basename "$path")
    ts=$(date +%Y%m%dT%H%M%S)
    echo "''${dir}/''${base}.''${ts}"
  '';
}
