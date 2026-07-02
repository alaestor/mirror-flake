{
  context,
  lib,
  pkgs,
}:
let
  scriptDirectory = ./scripts;
  scriptFiles = lib.filter (
    file: lib.hasSuffix ".nix" (toString file)
  ) (lib.filesystem.listFilesRecursive scriptDirectory);

  scripts = map (
    file:
    let
      fileName = builtins.baseNameOf file;
      script = import file { inherit context; };
      expectedName = lib.removeSuffix ".nix" fileName;
    in
    if script.name != expectedName then
      throw "cryptid script ${toString file} declares the mismatched name ${script.name}"
    else if !(builtins.elem script.category [
      "helper"
      "lesser"
      "greater"
      "internal"
    ]) then
      throw "cryptid script ${toString file} has unknown category ${script.category}"
    else
      script
  ) scriptFiles;

  visibleScripts = lib.filter (script: !script.hidden) scripts;
  scriptsIn = category: lib.filter (script: script.category == category) visibleScripts;

  renderScript = script: "  ${script.name} -- ${script.description}";
  renderCategory =
    category:
    lib.concatMapStringsSep "\n" renderScript (scriptsIn category);

  helpText = ''
    *************
    ** CRYPTID **              version ${context.version}
    *************

    Bootable Offline NixOS for cryptographic ID management

    Helper scripts

      ? -- print this menu
    ${renderCategory "helper"}

    Lesser scripts: tool operation abstractions

    ${renderCategory "lesser"}

    Greater scripts: workflow compositions

    ${renderCategory "greater"}

    ______________________________________________________

    Persistent storage is mounted at: ${context.path-mount-persist}/
    The vault, once opened, will be mounted at: ${context.path-mount-vault}/
    ______________________________________________________

    'root' has an empty password. '${context.username}' password is 'pass'.

  '';

  mkScript =
    script:
    pkgs.writeShellScriptBin script.name ''
      printf "\n— ${script.name} —\n"
      set -eo pipefail
      # workaround: wrapper to allow 'return' because 'exit' is problematic when used with 'source'
      _impl() {
      ${script.content}
      }
      _impl "$@"
    '';

  mkPackage =
    script:
    if script.wrapped then
      mkScript script
    else
      pkgs.writeShellScriptBin script.name script.content;
in
{
  inherit helpText scripts;

  packages = (map mkPackage scripts) ++ [
    (pkgs.writeShellScriptBin "?" ''
      cat <<'EOF'
      ${helpText}
      EOF
    '')
  ];
}
