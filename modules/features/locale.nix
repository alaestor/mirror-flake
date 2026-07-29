{...}:{

  # TODO: merge into global config
  flake.modules.nixos.locale = let
    default_locale = "en_CA.UTF-8";
  in
  {
    time.timeZone = "America/Toronto";

    i18n = {
      defaultLocale        = default_locale;
      extraLocaleSettings  = {
        LC_ADDRESS         = default_locale;
        LC_IDENTIFICATION  = default_locale;
        LC_MEASUREMENT     = default_locale;
        LC_MONETARY        = default_locale;
        LC_NAME            = default_locale;
        LC_NUMERIC         = default_locale;
        LC_PAPER           = default_locale;
        LC_TELEPHONE       = default_locale;
        LC_TIME            = default_locale;
      };
    };
  };

}
