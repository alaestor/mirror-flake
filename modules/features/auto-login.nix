{ ... }: let module-name = "auto-login"; in {
  flake.modules.nixos.${module-name} =
    { config, lib, ... }:
    let
      cfg = config.${module-name};
    in
    {
      options.${module-name}.user = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = config.hostIdentity.primaryUser;
          defaultText = lib.literalExpression "config.hostIdentity.primaryUser";
          description = "The user automatically logged in by the display manager and getty.";
      };

      config = {
        services.displayManager.autoLogin = {
          enable = true;
          user = cfg.user;
        };

        services.getty.autologinUser = cfg.user;
      };
    };
}
