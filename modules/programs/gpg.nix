/** GnuPG, configured for smartcard/agent use. */
{
  flake.modules.homeManager.gpg =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      home.packages = [ pkgs.sequoia-sq ];

      programs.gpg = {
        enable = lib.mkDefault true;
        package = lib.mkDefault pkgs.gnupg;
        scdaemonSettings.disable-ccid = lib.mkDefault true;
        settings = {
          personal-cipher-preferences = lib.mkDefault "AES256 AES192 AES";
          personal-digest-preferences = lib.mkDefault "SHA512 SHA384 SHA256";
          personal-compress-preferences = lib.mkDefault "ZLIB BZIP2 ZIP Uncompressed";
          default-preference-list =
            lib.mkDefault "SHA512 SHA384 SHA256 AES256 AES192 AES ZLIB BZIP2 ZIP Uncompressed";
          cert-digest-algo = lib.mkDefault "SHA512";
          s2k-digest-algo = lib.mkDefault "SHA512";
          s2k-cipher-algo = lib.mkDefault "AES256";
          charset = lib.mkDefault "utf-8";
          no-comments = lib.mkDefault true;
          no-emit-version = lib.mkDefault true;
          no-greeting = lib.mkDefault true;
          keyid-format = lib.mkDefault "0xlong";
          list-options = lib.mkDefault "show-uid-validity";
          verify-options = lib.mkDefault "show-uid-validity";
          with-fingerprint = lib.mkDefault true;
          require-cross-certification = lib.mkDefault true;
          require-secmem = lib.mkDefault true;
          no-symkey-cache = lib.mkDefault true;
          armor = lib.mkDefault true;
          throw-keyids = lib.mkDefault true;
          disable-dirmngr = lib.mkDefault true;
        };
      };

      services.gpg-agent = {
        enable = lib.mkDefault true;
        enableSshSupport = lib.mkDefault true;
        enableScDaemon = lib.mkDefault true;
        pinentry.package = lib.mkDefault (if config.userEnvironment.hasGui then pkgs.pinentry-qt else pkgs.pinentry-curses);
        extraConfig = lib.mkDefault "allow-loopback-pinentry";

        # The Nushell configuration below supports alternate GPG implementations.
        enableBashIntegration = lib.mkDefault false;
        enableFishIntegration = lib.mkDefault false;
        enableNushellIntegration = lib.mkDefault false;
        enableZshIntegration = lib.mkDefault false;
      };

      programs.nushell.extraConfig = lib.mkAfter ''
        $env.GPG_TTY = (tty)
        $env.SSH_AUTH_SOCK = $"(${config.programs.gpg.package}/bin/gpgconf --list-dirs agent-ssh-socket)"
        ${pkgs.gnupg}/bin/gpg-connect-agent --quiet updatestartuptty /bye | ignore
      '';
    };
}
