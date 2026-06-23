{
  /**
  Global configurations included automatically when using lib's `mk...` helpers
  */
  flake.modules.nixos.global-config = { pkgs, ... } : {
    nixpkgs.config.allowUnfree = true;
    environment.systemPackages = with pkgs; [
      neovim
    ];
  };
}
