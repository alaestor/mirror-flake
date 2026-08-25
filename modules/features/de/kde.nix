/**
  KDE Plasma 6 desktop environment, with Plasma Manager for user config.
*/
{ inputs, ... }:
let
  module-name = "kde";

  homeModule =
    { lib, ... }:
    {
      imports = [ inputs.plasma-manager.homeModules.plasma-manager ];
      programs.plasma = {
        enable = lib.mkDefault true;
      };
    };
in
{
  nucleus.inputs.plasma-manager = {
    url = "github:nix-community/plasma-manager";
    inputs.nixpkgs.follows = "unstable-nixpkgs";
    inputs.home-manager.follows = "unstable-home-manager";
  };

  flake.modules.homeManager.${module-name} = homeModule;

  flake.modules.nixos.${module-name} =
    { config, lib, pkgs, ... }:
    let
      cfg = config.${module-name};
    in
    {
      options.${module-name} = {
        excludePackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = with pkgs.kdePackages; [
            elisa
            khelpcenter
          ];
          description = "KDE packages excluded from the Plasma 6 environment.";
        };

        plasmaManager.enable = lib.mkEnableOption "Plasma Manager for this host's user environments" // {
          default = true;
        };
      };

      config = {
        environment.plasma6.excludePackages = cfg.excludePackages;

        services.desktopManager.plasma6.enable = true;

        services.displayManager = {
          defaultSession = "plasma";
          sddm = {
            enable = true;
            wayland = {
              enable = true;
              compositor = "kwin";
            };
          };
        };

        userEnvironment.sharedModules = lib.optional cfg.plasmaManager.enable homeModule;
      };
    };
}
