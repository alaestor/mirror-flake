{
  /**
    Global configurations included automatically into all hosts
  */
  flake.modules.nixos.global-config = { pkgs, lib, ... } :
  let
    default_locale = "en_CA.UTF-8";
    default_timezone = "America/Toronto";
  in
  {

    nix = {
      gc = {
        dates = "monthly";
        options = "--delete-older-than 90d";
        automatic = true;
      };
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

    time.timeZone = lib.mkDefault default_timezone;
    i18n = {
      defaultLocale        = lib.mkDefault default_locale;
      extraLocaleSettings  = {
        LC_ADDRESS         = lib.mkDefault default_locale;
        LC_IDENTIFICATION  = lib.mkDefault default_locale;
        LC_MEASUREMENT     = lib.mkDefault default_locale;
        LC_MONETARY        = lib.mkDefault default_locale;
        LC_NAME            = lib.mkDefault default_locale;
        LC_NUMERIC         = lib.mkDefault default_locale;
        LC_PAPER           = lib.mkDefault default_locale;
        LC_TELEPHONE       = lib.mkDefault default_locale;
        LC_TIME            = lib.mkDefault default_locale;
      };
    };

  };
}
