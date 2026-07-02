{ context }:
with context;
{
  name = "mkdirs";
  description = "Create the cryptid persistence directories.";
  category = "internal";
  wrapped = false;
  hidden = true;
  content = ''
    set -euo pipefail
    dirs=( ${builtins.concatStringsSep " " mkdirs} )
    for dir in "''${dirs[@]}"; do
      sudo mkdir -p "$dir"
    done
  '';
}
