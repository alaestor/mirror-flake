{
  flake.modules.homeManager.ssh =
    { lib, ... }:
    {
      programs.ssh = {
        enable = lib.mkDefault true;
        enableDefaultConfig = lib.mkDefault false;
        settings."*" = {
          ForwardAgent = lib.mkDefault false;
          AddKeysToAgent = lib.mkDefault "no";
        };
      };
    };
}
