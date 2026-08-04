let
  hasSuffix =
    suffix: value:
    let
      suffixLength = builtins.stringLength suffix;
      valueLength = builtins.stringLength value;
    in
    valueLength >= suffixLength
    && builtins.substring (valueLength - suffixLength) suffixLength value == suffix;

  listModules =
    directory:
    builtins.concatMap (
      name:
      let
        path = directory + "/${name}";
        type = builtins.readFileType path;
      in
      if builtins.substring 0 1 name == "_" then
        [ ]
      else if type == "directory" then
        listModules path
      else if hasSuffix ".nix" name then
        [ path ]
      else
        [ ]
    ) (builtins.attrNames (builtins.readDir directory));
in
listModules
