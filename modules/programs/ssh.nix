/** OpenSSH client program defaults, shared across host/user environments. */
{
  flake.modules.homeManager.ssh =
    { lib, options, ... }:
    let
      hasStructuredSettings = options.programs.ssh ? settings;
    in
    {
      programs.ssh =
        {
          enable = lib.mkDefault true;
        }
        // lib.optionalAttrs hasStructuredSettings {
          enableDefaultConfig = lib.mkDefault false;
          settings."*" = {
            ForwardAgent = lib.mkDefault false;
            AddKeysToAgent = lib.mkDefault "no";
          };
        }
        // lib.optionalAttrs (!hasStructuredSettings) {
          forwardAgent = lib.mkDefault false;
          addKeysToAgent = lib.mkDefault "no";
        };
    };
}
