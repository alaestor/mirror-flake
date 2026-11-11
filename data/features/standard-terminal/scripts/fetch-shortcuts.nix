{
  fetchPrograms,
  inputs,
  pkgs,
  ...
}:
let
  inherit (inputs.self) data;
  logo = data.vars.textart.boykisser;
  settings = pkgs.writeText "fastfetch-uwu.json" (
    builtins.replaceStrings [ "__NIX_REPLACED_LOGO_PATH__" ] [ (toString logo) ] (
      data.read "features/standard-terminal/fastfetch_uwu.json"
    )
  );
  wrap = name: runtimeInput: text: pkgs.writeShellApplication {
    inherit name text;
    runtimeInputs = [ runtimeInput ];
  };
in
{
  name = "fetch-shortcuts";
  enable = fetchPrograms != null;
  package = pkgs.symlinkJoin {
    name = "fetch-shortcuts";
    paths = [
      (wrap "ff" fetchPrograms.fastfetch.package ''exec fastfetch "$@"'')
      (wrap "ffuwu" fetchPrograms.fastfetch.package ''exec fastfetch -c "${settings}" "$@"'')
      (wrap "hy" fetchPrograms.hyfetch.package ''exec hyfetch "$@"'')
      (wrap "hyuwu" fetchPrograms.hyfetch.package ''
        exec hyfetch --ascii-file "${logo}" "$@" --args "-c ${settings}"
      '')
    ];
  };
}
