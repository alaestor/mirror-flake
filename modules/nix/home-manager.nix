{ inputs, ... } : {

  flake-file.inputs =
  let
    stable-version = "26.05";
  in
  {
    stable-home-manager = {
      url                          = "github:nix-community/home-manager/release-${stable-version}";
      inputs.nixpkgs.follows       = "stable-nixpkgs";
    };
    unstable-home-manager = {
      url                          = "github:nix-community/home-manager";
      inputs.nixpkgs.follows       = "unstable-nixpkgs";
    };
  };

  # for home-manage rebuilt with the system

  #flake.modules.nixos.stable-home-manager = {
  #  imports = [ inputs.stable-home-manager.flakeModules.home-manager ];
  #};

  #flake.modules.nixos.unstable-home-manager = {
  #  imports = [ inputs.unstable-home-manager.flakeModules.home-manager ];
  #};

}
