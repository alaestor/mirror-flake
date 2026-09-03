/**
  Personal identity defaults for the `alaestor` user: PGP fingerprint, Git
  author identity. Portable — safe to import on any host, including headless
  ones. Desktop theming lives separately in `alaestor-plasma`, which requires
  KDE Plasma 6.
*/
{ self, inputs, ... }:
{
  flake.modules.homeManager.alaestor = {
    pgp.primaryFingerprint = self.data.vars.identities.administrative.pgp.fingerprint;

    programs.git.settings.user = {
      name = "Alaestor Weissman";
      email = "alaestor@0x04.cc";
    };
  };

  /**
    Alaestor's KDE Plasma 6 desktop theming and app preferences. Requires
    `modules/features/de/kde.nix` (Plasma 6); importing this on a host
    without it is an evaluation error.
  */
  flake.modules.homeManager.alaestor-plasma =
    { pkgs, ... }:
    let
      # Leaf artifact from this author's personal package overlay; kept a
      # separate package boundary from the consumer's `pkgs`, same as
      # `app-config/mpv.nix`.
      mousetiler = inputs.alpkgs.packages.${pkgs.stdenv.hostPlatform.system}.mousetiler;
    in
    {
    programs.plasma = {
      workspace = {
        lookAndFeel = "org.kde.breezedark.desktop";
        colorScheme = "BreezeDark";
        cursor.theme = "Breeze_Light";
        soundTheme = "ocean";
        clickItemTo = "select";
      };
      input.keyboard = { repeatDelay = 250; repeatRate = 20; };
      kwin = {
        effects = {
          desktopSwitching.animation = "slide";
          windowOpenClose.animation = "off";
          wobblyWindows.enable = false;
          dimAdminMode.enable = true;
          dimInactive.enable = false;
          fallApart.enable = false;
          translucency.enable = true;
        };
        # This location follows Alaestor's personal desktop preferences.
        nightLight = {
          enable = true;
          mode = "location";
          location = { latitude = "43.0"; longitude = "-83.0"; };
          temperature = { day = 6500; night = 4800; };
          transitionTime = 10;
        };
        tiling.padding = 0;
        titlebarButtons.right = [ "keep-above-windows" "minimize" "maximize" "close" ];
      };
      spectacle.shortcuts = {
        captureEntireDesktop = "Shift+Print";
        captureRectangularRegion = "Print";
      };
      krunner = { position = "center"; historyBehavior = "enableAutoComplete"; };
      shortcuts.kwin = {
        "Window Close" = "Alt+F4";
        "Kill Window" = "Meta+Alt+F4";
        "Window Move Center" = "Meta+C";
        "Window Maximize" = "Meta+Up";
        "Window Minimize" = "Meta+Down";
        "Window Quick Tile Left" = "Meta+Left";
        "Window Quick Tile Right" = "Meta+Right";
        "Window Quick Tile Top" = "Meta+Shift+Up";
        "Window Quick Tile Bottom" = "Meta+Shift+Down";
        "Window One Screen to the Left" = [ ];
        "Window One Screen to the Right" = [ ];
      };
      configFile = {
        "kcminputrc"."Mouse"."cursorTheme" = "Breeze_Light";
        "kdeglobals"."KDE" = { "AnimationDurationFactor" = 0; "DoubleClickInterval" = 200; };
        "kdeglobals"."Shortcuts" = { "Close" = "Ctrl+Esc"; "ShowHideHiddenFiles" = "Ctrl+H"; "ShowMenubar" = ""; };
        "kded6rc"."Module-baloosearchmodule"."autoload" = true;
        "baloofilerc"."General" = { "only basic indexing" = true; "exclude filters version" = 9; };
        "krunnerrc"."Plugins" = { "baloosearchEnabled" = true; "krunner_webshortcutsEnabled" = false; };
        "klipperrc"."General" = { "KeepClipboardContents" = false; "MaxClipItems" = 1; "SelectionTextOnly" = false; };
        "kwalletrc"."Wallet"."Enabled" = true;
        "kiorc"."Confirmations" = { "ConfirmDelete" = true; "ConfirmEmptyTrash" = true; "ConfirmTrash" = false; };
        "kiorc"."Executable scripts"."behaviourOnLaunch" = "open";
        "kwinrc"."EdgeBarrier" = { "CornerBarrier" = false; "EdgeBarrier" = 0; };
        # Enables the mousetiler KWin script deployed via `home.file` below.
        # Plugin key must match its `metadata.json`'s `KPlugin.Id`.
        "kwinrc"."Plugins"."mousetilerEnabled" = true;
        "gwenviewrc"."General"."HistoryEnabled" = false;
        "gwenviewrc"."ImageView" = { "AnimationMethod" = "DocumentView::NoAnimation"; "NavigationEndNotification" = "NavigationEndNotification::AlwaysWarn"; };
        "gwenviewrc"."ThumbnailView"."ListVideos" = false;
        "dolphinrc"."ContentDisplay"."UsePermissionsFormat" = "NumericFormat";
        "dolphinrc"."General" = { "ViewMode" = 1; "SortingChoice" = "CaseInsensitiveSorting"; "ShowHideHiddenFiles" = true; "RememberOpenedTabs" = false; };
        "kdeglobals"."KFileDialog Settings" = {
          "Allow Expansion" = false; "Automatically select filename extension" = false;
          "Breadcrumb Navigation" = false; "Decoration position" = 2;
          "LocationCombo Completionmode" = 5; "PathCombo Completionmode" = 5;
          "Show Bookmarks" = false; "Show Full Path" = false; "Show Inline Previews" = false;
          "Show Preview" = false; "Show Speedbar" = true; "Show hidden files" = true;
          "Sort by" = "Name"; "Sort directories first" = true; "Sort hidden files last" = false;
          "Sort reversed" = false; "Speedbar Width" = 140; "View Style" = "DetailTree";
        };
        "okular-generator-popplerrc"."PDF Printing"."PrintScaleMode" = 1;
      };
      # Dolphin stores this setting in its filesystem state rather than config.
      dataFile."dolphin/view_properties/global/.directory".Settings.HiddenFilesShown = true;
    };

    programs = {
      elisa.enable = false;
      ghostwriter.enable = true;
      kate = {
        enable = true;
        editor = {
          inputMode = "vi";
          brackets = { automaticallyAddClosing = true; flashMatching = true; highlightMatching = false; highlightRangeBetween = false; };
          font = { family = "DejaVu Sans Mono"; pointSize = 12; };
        };
      };
      okular = { enable = true; general.obeyDrm = false; };
    };

    # `mousetiler`'s package root is the KWin script's KPackage layout
    # (metadata.json + contents/) as-is, so it drops straight into
    # scripts/mousetiler; KWin scripts don't need kpackagetool6 registration
    # the way full KPackage apps do, just files on disk plus the
    # `[Plugins]` flag above.
    #
    # Its tiling layout is still tuned live and stays out of Nix for now:
    # state lives in kwinrc's `[Script-mousetiler]` group, untracked here.
    home.file.".local/share/kwin/scripts/mousetiler" = {
      source = mousetiler;
      recursive = true;
    };
  };
}
