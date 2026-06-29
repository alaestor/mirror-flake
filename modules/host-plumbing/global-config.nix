{
  /**
    Global configurations included automatically into all hosts
  */
  flake.modules.nixos.global-config = { pkgs, ... } : {
    nix = {
      gc.automatic = true;
      optimise.automatic = true;
      settings = {
        auto-optimise-store = true;
        experimental-features = [ "nix-command" "flakes" ];
      };
    };
    nixpkgs.config.allowUnfree = true;
    environment.systemPackages = with pkgs; [
      neovim
    ];
  };
}
