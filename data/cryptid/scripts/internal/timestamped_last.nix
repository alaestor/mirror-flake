{ context }:
with context;
{
  name = "timestamped_last";
  description = "Return the newest timestamped path.";
  category = "internal";
  wrapped = false;
  hidden = true;
  content = ''
    set -euo pipefail
    path="$1"
    dir=$(dirname "$path")
    base=$(basename "$path")
    # lexicographically sort time-prefixed files and pick the last one
    last=$(find "$dir" -maxdepth 1 -name "''${base}.*" | sort | tail -n 1)
    if [ -z "$last" ]; then
        # Fallback: if no timestamped versions exist, complain but return the original path
        echo "Error: didn't find timestamp-version files; did the user run scripts out-of-order? Just returning '$1'" >&2
        echo "$path"
    else
        echo "$last"
    fi
  '';
}
