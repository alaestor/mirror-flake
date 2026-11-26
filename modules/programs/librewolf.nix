
/**
  LibreWolf with managed browser policy, bookmarks, search engines, and uBlock
  Origin rules. Add lasting uBlock exceptions to the rule file under `data/`.
  The browser retains cookies and site storage on exit so logins can persist.
  It also keeps browsing and download history so session restore can reopen
  tabs. DRM stays enabled for protected playback.
*/
{ self, ... }:
{
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
        settings = {
          "browser.uiCustomization.state"                         = builtins.replaceStrings ["\n" "  "] ["" ""] (self.data.read "programs/librewolf/firefox/uiCustomizationState.json");
          # Ask servers for other formats first. This does not disable WebP decoding.
          "image.http.accept"                                     = "image/avif,image/png,image/jpeg,*/*";
          "media.autoplay.blocking_policy"                        = 0; #  0=interaction, 1=interaction that times out, 3=click to play
          "findbar.highlightAll"                                  = true;
          "widget.gtk.overlay-scrollbars.enabled"                 = false; # static size, push content
        # One-off search buttons
          "browser.urlbar.shortcuts.bookmarks"                    = false;
          "browser.urlbar.shortcuts.history"                      = false;
        # Profile settings
          "security.sandbox.gpu.level"                            = 1;
          "privacy.donottrackheader.enabled"                      = true;
          "security.ssl.enable_false_start"                       = false;
          # Reset the old profile override. Post-handshake client auth interferes with HTTP/2.
          "security.tls.enable_post_handshake_auth"               = false;
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
      };
    };

    policies = { # see `about:policies#documentation`
      SearchBar = "unified";
      DisplayMenuBar = "default-off";
      DisplayBookmarksToolbar = "never";
    # Nix owns browser updates. Leave LibreWolf's updater defaults alone.
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
      PDFjs.Enabled = false;
     # behavior
      StartDownloadsInTempDirectory = true;         # LibreWolf default; stage downloads in temporary storage.
      PromptForDownloadLocation = true;             # LibreWolf default; always ask where to save.
      DontCheckDefaultBrowser = true;
      OfferToSaveLogins = false;
      HardwareAcceleration = true;                  # WARN(privacy): set false to resist more fingerprinting
      #OverrideFirstRunPage = "";
      #OverridePostUpdatePage = "";
      HttpsOnlyMode = "force_enabled";
      NetworkPrediction = false;
      #NoDefaultBookmarks = true;
      SearchSuggestEnabled = false;
      EncryptedMediaExtensions = {                  # Convenience: allow protected media playback.
        Enabled = true;
        Locked = true;
      };
      EnableTrackingProtection = {
        Value = true;
        Locked = true;
        Cryptomining = true;
        Fingerprinting = true;
        EmailTracking = true;
      };
      ClearOnShutdown = {
        BrowsingHistoryAndDownloads = false;         # Clearing history here also erases saved tabs.
        CookiesAndStorage = false;
        FormData = true;
        Cache = false;
        SiteSettings = false;                       # Keep site permissions.
      };

      SSLVersionMin = "tls1.2";                     # LibreWolf default; do not allow older TLS.
      # Leave certificate revocation to LibreWolf's CRLite and OCSP defaults.
      # Keep TLS 1.3 and TLS 1.2 ECDHE with AEAD. Disable CBC and static RSA.
      DisabledCiphers = {
        TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA = true;
        TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA = true;
        TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA = true;
        TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA = true;
        TLS_DHE_RSA_WITH_AES_128_CBC_SHA = true;
        TLS_DHE_RSA_WITH_AES_256_CBC_SHA = true;
        TLS_RSA_WITH_AES_128_CBC_SHA = true;
        TLS_RSA_WITH_AES_256_CBC_SHA = true;
        TLS_RSA_WITH_3DES_EDE_CBC_SHA = true;
        TLS_RSA_WITH_AES_128_GCM_SHA256 = true;
        TLS_RSA_WITH_AES_256_GCM_SHA384 = true;
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
        "xpinstall.signatures.required"                               = true; # LibreWolf default; require signed extensions.
        # LibreWolf default; lock strict protection for this profile.
        "browser.contentblocking.category"                            = { Value = "strict"; Status = "locked"; };
        "browser.aboutConfig.showWarning"                             = false;
        "browser.startup.page"                                        = 3; # Convenience: reopen tabs from the last session.
        "browser.uidensity"                                           = 1; # compact tab bar
        "browser.search.suggest.enabled"                              = false;
        "browser.search.suggest.enabled.private"                      = false;
        "browser.urlbar.suggest.engines"                              = false;
        "browser.urlbar.suggest.searches"                             = false;
        "browser.urlbar.suggest.clipboard"                            = false;
        "browser.urlbar.suggest.bookmark"                             = true;
        "browser.urlbar.showSearchSuggestionsFirst"                   = false;
        "browser.urlbar.autoFill.adaptiveHistory.enabled"             = true;
        "browser.urlbar.richSuggestions.featureGate"                  = false;
        "browser.urlbar.yelp.featureGate"                             = false;
        "browser.urlbar.mdn.featureGate"                              = false;
        "browser.urlbar.weather.featureGate"                          = false;
        "browser.urlbar.trending.featureGate"                         = false;
        "browser.uitour.enabled"                                      = false;
        # Keep download checks off even if site checks are enabled.
        "browser.safebrowsing.downloads.enabled"                      = false;
        "browser.safebrowsing.downloads.remote.enabled"               = false;
        "browser.toolbars.bookmarks.visibility"                       = "never";
        "browser.translations.enable"                                 = false;
        "browser.newtabpage.enabled"                                  = false;
        "browser.laterrun.enabled"                                    = false;
        "browser.rights.3.shown"                                      = true;
        "browser.dom.window.dump.enabled"                             = false;
        "privacy.userContext.enabled"                                 = true;
        "privacy.globalprivacycontrol.enabled"                        = true; # LibreWolf default; always send GPC.
        # security
        "extensions.quarantinedDomains.enabled"                       = true;
        "dom.private-attribution.submission.enabled"                  = false;
        "security.insecure_connection_text.enabled"                   = true;
        "security.insecure_connection_text.pbmode.enabled"            = true;
        "security.ssl.require_safe_negotiation"                       = true; # LibreWolf default; require secure renegotiation.
        "security.tls.hello_downgrade_check"                           = true; # LibreWolf default; detect downgrades.
        "security.tls.enable_0rtt_data"                                = false; # LibreWolf default; avoid replayable early data.
        "gfx.webrender.all"                                           = true;
        "browser.send_pings"                                          = false;
        "network.connectivity-service.enabled"                        = false;
        "network.http.speculative-parallel-limit"                     = 0;
        "network.trr.mode"                                            = 5;
        "security.tls.version.enable-deprecated"                      = false; # LibreWolf default; disallow the legacy fallback.
        "dom.battery.enabled"                                         = false;
        "dom.security.https_only_mode_pbm"                            = true;
        "dom.security.https_only_mode_send_http_background_request"   = false;

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
