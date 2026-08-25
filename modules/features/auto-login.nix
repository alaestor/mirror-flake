{ ... }:
let
  module-name = "auto-login";
in
{
  flake.modules.nixos.${module-name} =
    { config, lib, ... }:
    let
      cfg = config.${module-name};
    in
    {
      options.${module-name} = {
        user = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = config.hostIdentity.primaryUser;
          defaultText = lib.literalExpression "config.hostIdentity.primaryUser";
          description = "The user automatically logged in by the display manager and getty.";
        };

        getty.enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether to also auto-login on getty (any VT, including one
            reached by switching away from a broken graphical session).
            This is a second, independent unlocked-shell surface beyond the
            display manager; disable it to keep only the display manager
            auto-login.
          '';
        };
      };

      config = {
        services.displayManager.autoLogin = {
          enable = true;
          user = cfg.user;
        };

        services.getty.autologinUser = lib.mkIf cfg.getty.enable cfg.user;
      };
    };
}
