{ ... }:
let
  module-name = "lxqt";
in
{
  flake.modules.nixos.${module-name} =
    { config, lib, ... }:
    let
      cfg = config.${module-name};
    in
    {
      options.${module-name} = {
        lightdm.enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to use LightDM as the display manager for the LXQt session.";
        };
      };

      config = {
        services = {
          xserver = {
            enable = true;
            desktopManager.lxqt.enable = true;
            displayManager.lightdm.enable = cfg.lightdm.enable;
            xkb = {
              layout = "us";
              variant = "";
            };
          };
          displayManager.defaultSession = "lxqt";
        };
      };
    };
}
