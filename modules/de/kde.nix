{ inputs, ... }:
let
  module-name = "kde";

  homeModule =
    { lib, ... }:
    {
      imports = [ inputs.plasma-manager.homeModules.plasma-manager ];
      programs.plasma = {
        enable = lib.mkDefault true;

        workspace = {
          lookAndFeel = lib.mkDefault "org.kde.breezedark.desktop";
          colorScheme = lib.mkDefault "BreezeDark";
          cursor.theme = lib.mkDefault "Breeze_Light";
          soundTheme = lib.mkDefault "ocean";
          clickItemTo = lib.mkDefault "select";
        };

        input = {
          mice = [
            { # TODO: this should be scoped to APC host...
              enable = true;
              name = "Logitech, Inc. USB Receiver";
              acceleration = 0.0;
              accelerationProfile = "none";
              naturalScroll = false;
              scrollSpeed = 1;
              leftHanded = false;
              middleButtonEmulation = false;
              vendorId = "046d";
              productId = "c547";
            }
          ];
          keyboard = {
            repeatDelay = 250;
            repeatRate = 20;
          };
        };

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
          nightLight = {
            enable = true;
            mode = "location";
            location = {
              latitude = "43.0";
              longitude = "-83.0";
            };
            temperature = {
              day = 6500;
              night = 4800;
            };
            transitionTime = 10;
          };
          tiling.padding = 0;
          titlebarButtons.right = [
            "keep-above-windows"
            "minimize"
            "maximize"
            "close"
          ];
        };

        spectacle.shortcuts = {
          captureEntireDesktop = "Shift+Print";
          captureRectangularRegion = "Print";
        };

        krunner = {
          position = "center";
          historyBehavior = "enableAutoComplete";
        };

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
          "kcminputrc"."Mouse"."XLbInptPointerAcceleration" = 0;
          "kdeglobals"."KDE"."AnimationDurationFactor" = 0;
          "kdeglobals"."KDE"."DoubleClickInterval" = 200;
          "kdeglobals"."Shortcuts"."Close" = "Ctrl+Esc";
          "kdeglobals"."Shortcuts"."ShowHideHiddenFiles" = "Ctrl+H";
          "kdeglobals"."Shortcuts"."ShowMenubar" = "";
          "kded5rc"."Module-baloosearchmodule"."autoload" = true;
          "baloofilerc"."General"."only basic indexing" = true;
          "baloofilerc"."General"."exclude filters version" = 9;
          "krunnerrc"."Plugins"."baloosearchEnabled" = true;
          "krunnerrc"."Plugins"."krunner_webshortcutsEnabled" = false;
          "klipperrc"."General"."KeepClipboardContents" = false;
          "klipperrc"."General"."MaxClipItems" = 1;
          "klipperrc"."General"."SelectionTextOnly" = false;
          "kwalletrc"."Wallet"."Enabled" = true;
          "kiorc"."Confirmations"."ConfirmDelete" = true;
          "kiorc"."Confirmations"."ConfirmEmptyTrash" = true;
          "kiorc"."Confirmations"."ConfirmTrash" = false;
          "kiorc"."Executable scripts"."behaviourOnLaunch" = "open";
          "kwinrc"."EdgeBarrier"."CornerBarrier" = false;
          "kwinrc"."EdgeBarrier"."EdgeBarrier" = 0;
          "gwenviewrc"."General"."HistoryEnabled" = false;
          "gwenviewrc"."ImageView"."AnimationMethod" = "DocumentView::NoAnimation";
          "gwenviewrc"."ImageView"."NavigationEndNotification" = "NavigationEndNotification::AlwaysWarn";
          "gwenviewrc"."ThumbnailView"."ListVideos" = false;
          "dolphinrc"."ContentDisplay"."UsePermissionsFormat" = "NumericFormat";
          "dolphinrc"."General"."ViewMode" = 1;
          "dolphinrc"."General"."SortingChoice" = "CaseInsensitiveSorting";
          "dolphinrc"."General"."ShowHideHiddenFiles" = true; # TODO: doesn't work, see +25~26 lines bellow
          "dolphinrc"."General"."RememberOpenedTabs" = false;
          "kdeglobals"."KFileDialog Settings" = {
            "Allow Expansion" = false;
            "Automatically select filename extension" = false;
            "Breadcrumb Navigation" = false;
            "Decoration position" = 2;
            "LocationCombo Completionmode" = 5;
            "PathCombo Completionmode" = 5;
            "Show Bookmarks" = false;
            "Show Full Path" = false;
            "Show Inline Previews" = false;
            "Show Preview" = false;
            "Show Speedbar" = true;
            "Show hidden files" = true;
            "Sort by" = "Name";
            "Sort directories first" = true;
            "Sort hidden files last" = false;
            "Sort reversed" = false;
            "Speedbar Width" = 140;
            "View Style" = "DetailTree";
          };
          "okular-generator-popplerrc"."PDF Printing"."PrintScaleMode" = 1;
        };

        # TODO: this doesn't work because dolphin stores this weirdly in the filesystem itself
        dataFile."dolphin/view_properties/global/.directory".Settings.HiddenFilesShown = true;
      };

      programs.elisa.enable = false;
      programs.ghostwriter.enable = true;
      programs.kate = {
        enable = true;
        editor = {
          inputMode = "vi";
          brackets = {
            automaticallyAddClosing = true;
            flashMatching = true;
            highlightMatching = false;
            highlightRangeBetween = false;
          };
          font = {
            family = "DejaVu Sans Mono";
            pointSize = 12;
          };
        };
      };
      programs.okular = {
        enable = true;
        general.obeyDrm = false;
      };
    };
in
{
  flake-file.inputs.plasma-manager = {
    url = "github:nix-community/plasma-manager";
    inputs.nixpkgs.follows = "unstable-nixpkgs";
    inputs.home-manager.follows = "unstable-home-manager";
  };

  flake.modules.homeManager.${module-name} = homeModule;

  flake.modules.nixos.${module-name} =
    { config, lib, pkgs, ... }:
    let
      cfg = config.${module-name};
    in
    {
      options.${module-name} = {
        excludePackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = with pkgs.kdePackages; [
            elisa
            khelpcenter
          ];
          description = "KDE packages excluded from the Plasma 6 environment.";
        };

        plasmaManager.enable = lib.mkEnableOption "Plasma Manager for this host's user environments" // {
          default = true;
        };
      };

      config = {
        environment.plasma6.excludePackages = cfg.excludePackages;

        services.desktopManager.plasma6.enable = true;

        services.displayManager = {
          defaultSession = "plasma";
          sddm = {
            enable = true;
            wayland = {
              enable = true;
              compositor = "kwin";
            };
          };
        };

        userEnvironment.sharedModules = lib.optional cfg.plasmaManager.enable homeModule;
      };
    };
}
