
/*
  random example:
    https://discourse.nixos.org/t/declare-firefox-extensions-and-settings/36265
    https://discourse.nixos.org/t/add-custom-addons-to-firefox-directly-from-https-addons-mozilla-org/48730
    https://gitlab.com/engmark/root/-/blob/60468eb82572d9a663b58498ce08fafbe545b808/configuration.nix#L293-310
    https://github.com/Kreyren/nixos-config/blob/bd4765eb802a0371de7291980ce999ccff59d619/nixos/users/kreyren/home/modules/web-browsers/firefox/firefox.nix
    https://gist.github.com/jornane/f47c344bae4c04ac761ee48b0b88c869
    https://github.com/arkenfox
*/

{ inputs, self, ... }:
{
  flake-file.inputs.firefox-extensions-declarative = {
    url = "github:firefox-extensions-declarative/firefox-extensions-declarative";
    inputs.nixpkgs.follows = "unstable-nixpkgs";
  };

  flake.modules.homeManager.librewolf =
    { lib, pkgs, ... }:
    let
      default-profile-name = "default";
    in
    {
      programs.librewolf = {
        enable = lib.mkDefault true;
        package = lib.mkDefault pkgs.librewolf;

        languagePacks = [ ];

    profiles = {
      "${default-profile-name}" = {
        id = 0;
        name = "${default-profile-name}";
        isDefault = true;
        extensions.packages = [
          inputs.firefox-extensions-declarative.packages.${pkgs.stdenv.hostPlatform.system}.stylus-declarative
        ];
        settings = {
          "extensions.autoDisableScopes"                          = 0; # automatically enable installed extensions
          "browser.uiCustomization.state"                         = builtins.replaceStrings ["\n" "  "] ["" ""] (self.data.read "programs/librewolf/firefox/uiCustomizationState.json");
          "image.http.accept"                                     = "image/avif,image/png,image/jpeg,*/*"; # try to dissuade webp...
          "media.autoplay.blocking_policy"                        = 0; #  0=interaction, 1=interaction that times out, 3=click to play
          "findbar.highlightAll"                                  = true;
          "general.smoothScroll"                                  = false;
          "widget.gtk.overlay-scrollbars.enabled"                 = false; # static size, push content
        # One-off search buttons
          "browser.urlbar.shortcuts.bookmarks"                    = false;
          "browser.urlbar.shortcuts.history"                      = false;
          "browser.urlbar.shortcuts.tabs"                         = false;
        # these settings can't be in firefox's global policies
          "security.sandbox.gpu.level"                            = 1;
          "privacy.donottrackheader.enabled"                      = true;
          "devtools.debugger.remote-enabled"                      = false;
          "security.cert_pinning.enforcement_level"               = 2;
          "security.pki.crlite_mode"                              = 2;
          "security.remote_settings.crlite_filters.enabled"       = true;
          "security.ssl.enable_false_start"                       = false;
          "security.ssl.disable_session_identifiers"              = false;
          "security.tls.enable_post_handshake_auth"               = true;
          # weak ssl ciphers
          "security.ssl3.deprecated.rsa_des_ede3_sha"             = false;
          "security.ssl3.dhe_rsa_aes_128_sha"                     = false;
          "security.ssl3.dhe_rsa_aes_256_sha"                     = false;
          "security.ssl3.ecdhe_rsa_aes_128_sha"                   = false;
          "security.ssl3.ecdhe_rsa_aes_256_sha"                   = false;
          # these are inheritted by TLS:
          "security.ssl3.rsa_aes_128_sha"                         = false;
          "security.ssl3.rsa_aes_256_sha"                         = false;
          "security.ssl3.ecdhe_ecdsa_aes_128_sha"                 = false;
          "security.ssl3.ecdhe_ecdsa_aes_256_sha"                 = false;
          # "good enough"
          #"security.ssl3.rsa_aes_128_gcm_sha256"                 = false;
          #"security.ssl3.rsa_aes_256_gcm_sha384"                 = false;
          #"security.ssl3.ecdhe_ecdsa_aes_128_gcm_sha256"         = false;
          #"security.ssl3.ecdhe_rsa_aes_128_gcm_sha256"           = false;
          #"security.ssl3.ecdhe_rsa_aes_256_gcm_sha384"           = false;
          #"security.ssl3.ecdhe_ecdsa_aes_256_gcm_sha384"         = false;
          #"security.ssl3.ecdhe_ecdsa_chacha20_poly1305_sha256"   = false;
          #"security.ssl3.ecdhe_rsa_chacha20_poly1305_sha256"     = false;
        };

        search    = import (self.data.path "programs/librewolf/firefox/searchengines.nix");
        bookmarks = {
          force = true;
          settings = import (self.data.path "programs/librewolf/firefox/bookmarks.nix");
        };

        containersForce = true;
        containers = {
          Personal = {
            color = "blue";
            icon = "fingerprint";
            id = 1;
          };
          Caution = {
            color = "red";
            icon = "fence";
            id = 2;
          };
          Commerce = {
            color = "orange";
            icon = "cart";
            id = 3;
          };
          Discord = {
            color = "purple";
            icon = "circle";
            id = 4;
          };
        };
        #*/
      };
    };

    policies = { # see `about:policies#documentation`
      SearchBar = "unified";
      DisplayMenuBar = "default-off";
      DisplayBookmarksToolbar = "never";
    # updaters
      AppAutoUpdate = false;
      BackgroundAppUpdate = false;
      #ExtensionUpdate = false;
      DisableAppUpdate = true;
      DisableSystemAddonUpdate = true;
    # 'features'
      PasswordManagerEnabled = false;
      AutofillAddressEnabled = false;
      AutofillCreditCardEnabled = false;
      DisablePocket = true;
      DisableTelemetry = true;
      DisableAccounts = true;
      DisableFirefoxAccounts = true;                # sync
      DisableFirefoxStudies = true;
      DisableFirefoxScreenshots = true;
      DisableFeedbackCommands = true;
      DisableFormHistory = true;
      DisableMasterPasswordCreation = true;         # since we're disabling passwords anyways
      DisableProfileImport = true;                  # profiles should be handled by nix
      DisableProfileRefresh = true;
      DisableSetDesktopBackground = true;           # The set-wallpaper context menu item for images
      DisablePasswordReveal = false;                # WARN(security): should disable
      DisableBuiltinPDFViewer = true;
      PDFjs = {
        Enabled = false;
        EnablePermissions = false;
      };
     # behavior
      StartDownloadsInTempDirectory = true;
      PromptForDownloadLocation = true;             # require user action
      DontCheckDefaultBrowser = true;
      PostQuantumKeyAgreementEnabled = true;
      OfferToSaveLogins = false;
      HardwareAcceleration = true;                  # WARN(privacy): set false to resist more fingerprinting
      #OverrideFirstRunPage = "";
      #OverridePostUpdatePage = "";
      HttpsOnlyMode = "force_enabled";
      NetworkPrediction = false;
      #NoDefaultBookmarks = true;
      SearchSuggestEnabled = false;
      EncryptedMediaExtensions = {                  # WARN(freedom): DRM is enabled
        Enabled = true;
        Locked = true;
      };
      EnableTrackingProtection = {
        Value = true;
        Locked = true;
        Cryptomining = true;
        Fingerprinting = true;
        EmailTracking = true;
        SocialTracking = true;                      # WARN(compatibility): blocking may cause issues
      };
      SanitizeOnShutdown = {
        Locked = true;
      # keep
        History = false;                            # WARN(privacy): local threat liability
        Cookies = false;                            # WARN(security): local threat liability
        Sessions = false;                           # WARN(security): local threat liability
        SiteSettings = false;
      # purge
        Cache = false;
        Downloads = true;
        FormData = true;
        OfflineApps = true;
      };

      UserMessaging = {
        Locked                   = true;
        SkipOnboarding           = true;  # Don’t show onboarding messages on the new tab page
        ExtensionRecommendations = false; # Don’t recommend extensions while the user is visiting web pages
        FeatureRecommendations   = false; # Don’t recommend browser features
        MoreFromMozilla          = false; # Don’t show the “More from Mozilla” section in Preferences
        UrlbarInterventions      = false; # Don’t offer suggestions in the URL bar
        WhatsNew                 = false; # Remove the “What’s New” icon and menuitem
      };

      UseSystemPrintDialog = true;

      Handlers = { mimeTypes."application/pdf".action = "saveToDisk"; };

      PictureInPicture = {
        Locked  = true;
        Enabled = false;
      };

      FirefoxSuggest = {
        Locked               = true;
        ImproveSuggest       = false;
        WebSuggestions       = false;
        SponsoredSuggestions = false;
      };

      ExtensionSettings =
      let

        block = uuid: { # explicit block; not used because I'm doing an allow-list
          name = uuid;
          value = {
            installation_mode = "blocked";
            blocked_install_message = "This extension is set to be blocked by your Nix configuration.";
          };
        };

        allow = shortId: uuid: { # uuid is unused but kept to easily refactor allow->install
          name = uuid;
          value = { installation_mode = "allowed"; };
        };

        install = shortId: uuid: {
          name = uuid;
          value = {
            install_url = "https://addons.mozilla.org/en-US/firefox/downloads/latest/${shortId}/latest.xpi";
            installation_mode = "force_installed";
          };
        };

      in builtins.listToAttrs [
        { # W-ARN(security): user liability; should disallow addon installations
          name = "*";
          value = {
            allowed_types = ["extension"];
            installation_mode = "blocked";
            blocked_install_message = "Only extensions that are allow-listed in your Nix configuration are permitted.";
          };
        }
      # plumbing & passives
        (install "ublock-origin"                  "uBlock0@raymondhill.net")
        (install "source-identifier-sanitizer"    "{9a43c815-00db-4766-9ed0-a0ece4f37639}")
        (install "istilldontcareaboutcookies"     "idcac-pub@guus.ninja")
        (allow   "localcdn-fork-of-decentraleyes" "{b86e4813-687a-43e6-ab65-0bde4ab75758}")
      # utility
        (allow   "live-cat"                       "{e7b1fc1c-aad2-4f76-8f35-4ee8702b89e9}")
        (allow   "absolute-enable-right-click"    "{9350bc42-47fb-4598-ae0f-825e3dd9ceba}")
        (allow   "cookie-quick-manager"           "{60f82f00-9ad5-4de5-b31c-b16a47c51558}")
        (allow   "user-agent-string-switcher"     "{a6c4a591-f1b2-4f03-b3ff-767e5bedf4e7}")
        (allow   "tabzen"                         "tabzen@tabzen.org")
        (allow   "stylus-declarative"             "{7a7a4a92-a2a0-41d1-9fd7-1e92480d612d}") # NOTE: unsigned, requires setting `xpinstall.signatures.required = false`
        (allow   "wayback-machine_new"            "wayback_machine@mozilla.org")
        (allow   "proton-vpn-firefox-extension"   "vpn@proton.ch")
        (allow   "darkreader"                     "addon@darkreader.org")
        (allow   "link-gopher"                    "linkgopher@oooninja.com")
        (allow   "proton-pass"                    "78272b6fa58f4a1abaac99321d503a20@proton.me")
        (allow   "tampermonkey"                   "firefox@tampermonkey.net")
        (allow   "tampermonkey-editors"           "editor-firefox@tampermonkey.net")
      # io
        (allow   "kagi-search-for-firefox"        "search@kagi.com")
        (allow   "kagi-privacy-pass"              "privacypass@kagi.com")
        (allow   "web-clipper-obsidian"           "clipper@obsidian.md")
        (allow   "keepassxc-browser"              "keepassxc-browser@keepassxc.org")
        (allow   "plasma-integration"             "plasma-browser-integration@kde.org")
        (allow   "lm-studio-sidebar"              "lm-studio-sidebar@your-email.com")
      # site specific
        # gh
        (allow   "github-file-icons"              "{85860b32-02a8-431a-b2b1-40fbd64c9c69}")
        (allow   "lovely-forks"                   "github-forks-addon@musicallyut.in")
        (allow   "enhanced-github"                "{72bd91c9-3dc5-40a8-9b10-dec633c0873f}")
        # yt
        (install "sponsorblock"                   "sponsorBlocker@ajay.app")
        (install "return-youtube-dislikes"        "{762f9885-5a13-4abd-9c77-433dcd38b8fd}")
        (install "youtube-shorts-redirect"        "{cf485034-0bda-470d-a027-794f3214359c}") # youtube-shorts-block is more popular but heavier and more prone to breakage
        (allow   "no-yt-premieres"                "{0cb73282-9781-4b9c-83e4-26628e1a02ca}")
        # steam
        (allow   "protondb-for-steam"             "{30280527-c46c-4e03-bb16-2e3ed94fa57c}")
      ];

      "3rdparty".Extensions = {
        "{7a7a4a92-a2a0-41d1-9fd7-1e92480d612d}".styles = [
          {
            code = self.data.read "programs/librewolf/stylus/opentogethertube.user.css";
          }
        ];

        "uBlock0@raymondhill.net".adminSettings = {
          userSettings = {
            uiTheme = "dark";
            uiAccentCustom = true;
            uiAccentCustom0 = "#8300ff";
            cloudStorageEnabled = false;
            advancedUserEnabled = true;
            firewallPaneMinimized = false;
            ignoreGenericCosmeticFilters = false; # WARN(performance): set true for low-power devices
            #importedLists = []; # https://github.com/gorhill/uBlock/wiki/Filter-lists-from-around-the-web
            #externalLists = lib.concatStringsSep "\n" importedLists;
          };
          selectedFilterLists    = lib.splitString "\n" (self.data.read "programs/librewolf/ublock/filterLists.txt");
          userFilters            = self.data.read "programs/librewolf/ublock/userFilters.txt";
          dynamicFilteringString = self.data.read "programs/librewolf/ublock/dynamicFilters.txt";
        };
      };

      Preferences = { # about:config (verify using about:policies#errors ; some settings must be defined in the profile rather than as a global policy)
        # ui
        "extensions.activeThemeID"                                    = "firefox-compact-dark@mozilla.org";
        # general
        "xpinstall.signatures.required"                               = false; # WARN(security): degrades posture but required for unsigned declarative-fork extensions.
        "browser.contentblocking.category"                            = { Value = "strict"; Status = "locked"; };
        "browser.aboutConfig.showWarning"                             = false;
        "browser.startup.page"                                        = 3; # Resume
        "browser.uidensity"                                           = 1; # compact tab bar
        "browser.search.suggest.enabled"                              = false;
        "browser.search.suggest.enabled.private"                      = false;
        "browser.urlbar.suggest.engines"                              = false;
        "browser.urlbar.suggest.searches"                             = false;
        "browser.urlbar.suggest.clipboard"                            = false;
        "browser.urlbar.suggest.bookmark"                             = true;
        "browser.urlbar.suggest.quicksuggest"                         = true;
        "browser.urlbar.quicksuggest.enabled"                         = true;
        "browser.urlbar.quicksuggest.scenario"                        = "history";
        "browser.urlbar.showSearchSuggestionsFirst"                   = false;
        "browser.urlbar.autoFill.adaptiveHistory.enabled"             = true;
        "browser.urlbar.richSuggestions.featureGate"                  = false;
        "browser.urlbar.yelp.featureGate"                             = false;
        "browser.urlbar.mdn.featureGate"                              = false;
        "browser.urlbar.weather.featureGate"                          = false;
        "browser.urlbar.trending.featureGate"                         = false;
        "browser.download.useDownloadDir"                             = true;
        "browser.download.start_downloads_in_tmp_dir"                 = true;
        "browser.helperApps.deleteTempFileOnExit"                     = true;
        "browser.uitour.enabled"                                      = false;
        "browser.safebrowsing.downloads.enabled"                      = true;
        "browser.safebrowsing.downloads.remote.enabled"               = false;
        "browser.toolbars.bookmarks.visibility"                       = "never";
        "browser.translations.enable"                                 = false;
        "browser.newtabpage.enabled"                                  = false;
        "browser.laterrun.enabled"                                    = false;
        "browser.rights.3.shown"                                      = true;
        "browser.dom.window.dump.enabled"                             = false;
        "privacy.userContext.enabled"                                 = true;
        "privacy.globalprivacycontrol.enabled"                        = true;
        # security
        "extensions.quarantinedDomains.enabled"                       = true;
        "dom.private-attribution.submission.enabled"                  = false;
        "security.insecure_connection_text.enabled"                   = true;
        "security.insecure_connection_text.pbmode.enabled"            = true;
        "security.ssl.require_safe_negotiation"                       = true;
        "security.tls.hello_downgrade_check"                          = false;
        "security.tls.enable_0rtt_data"                               = false;
        "security.pki.certificate_transparency.mode"                  = 2;
        "security.OCSP.enabled"                                       = 1;
        "security.OCSP.require"                                       = true;
        "gfx.webrender.all"                                           = true;
        "browser.send_pings"                                          = false;
        "network.http.spdy.enabled"                                   = false;
        "network.connectivity-service.enabled"                        = false;
        "network.cookie.cookieBehavior.optInPartitioning"             = true;
        "network.http.speculative-parallel-limit"                     = 0;
        "network.trr.mode"                                            = 5;
        "security.tls.version.enable-deprecated"                      = false;
        "dom.battery.enabled"                                         = false;
        "dom.security.https_only_mode"                                = true;
        "dom.security.https_only_mode_pbm"                            = true;
        "dom.security.https_only_mode_ever_enabled"                   = true;
        "dom.security.https_only_mode_ever_enabled_pbm"               = true;
        "dom.security.https_only_mode.upgrade_local"                  = true;
        "dom.security.https_only_mode_send_http_background_request"   = false;
        # WARN(security): local threat liability; disable disk caching
        /*
        "browser.cache.offline.enable"                                = false;
        "browser.cache.disk.enable"                                   = false;
        "browser.cache.disk_cache_ssl"                                = false;
        "browser.cache.memory.enable"                                 = false;
        "browser.cache.insecure.enable"                               = false;
        */

        # ux
        "browser.warnOnQuitShortcut"                                  = false;
        "accessibility.browsewithcaret_shortcut.enabled"              = false;
        "media.hardwaremediakeys.enabled"                             = false;
        #"media.autoplay.default"                                      = 5; # Disabled
        "general.smoothScroll"                                        = false;

        # ui
        "browser.uiCustomization.horizontalTabstrip"                  = ''["tabbrowser-tabs","alltabs-button","new-tab-button","new-window-button"]'';
        "sidebar.verticalTabs"                                        = true;
        "sidebar.verticalTabs.dragToPinPromo.dismissed"               = true;
        "browser.urlbar.shortcuts.tabs"                               = false;

      };
    };

      };
    };
}
