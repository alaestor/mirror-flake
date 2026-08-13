{
  /**
    Global configurations included automatically into all hosts of a class.
    Each class states the same intent in its own platform vocabulary; neither
    export is a reusable feature, and hosts never import them explicitly.
  */

  flake.modules.nixos.global-config = { pkgs, lib, ... } :
  let
    default_locale = "en_CA.UTF-8";
    default_timezone = "America/Toronto";
  in
  {

    nix = {
      gc = {
        dates = lib.mkDefault "monthly";
        options = lib.mkDefault "--delete-older-than 90d";
        automatic = lib.mkDefault true;
      };
      optimise.automatic = lib.mkDefault true;
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

  flake.modules.nixOnDroid.global-config = { pkgs, ... }:
  {

    environment = {
      etcBackupExtension = ".bak";
      packages = with pkgs; [
        busybox
        git
        neovim
      ];
    };

    nix.extraOptions = ''
      experimental-features = nix-command flakes
    '';

    nix.nixPath = [ "nixpkgs=${pkgs.path}" ]; # TODO(workaround): nix-on-droid flakes dont expose nixpkgs in NIX_PATH; see [nix-on-droid#499](https://github.com/nix-community/nix-on-droid/issues/499)

  };
}
