{ pkgs, ... }:
let
  # TODO(pkgs): migrate ffmpeg-hdr
  ffmpeg-hdr =
    (pkgs.ffmpeg-headless.override {
      withUnfree = false;
      withTensorflow = false;
      withSmallBuild = false;
      withDebug = false;
      withSrt = false;
      withSsh = false;
      withRist = false;
      withGmp = false;
      withQrencode = false;
      withQuirc = false;
      withAom = false;
      withDav1d = false;
      withRav1e = false;
      withJxl = true;
      withSvtav1 = true;
      svt-av1 = pkgs.svt-av1-hdr;
    }).overrideAttrs
      (_: {
        pname = "ffmpeg-hdr";
      });
in
{
  ssh-client.identityFiles = [
    "~/.ssh/ssh_sk"
    "~/.ssh/id_ed25519_apc"
  ];

  home = {
    # This account was created under Home Manager 23.11, predating apc's
    # own declared stateVersion ("24.05" in modules/host/apc.nix) — do not
    # sync this to the host baseline; it's compatibility metadata for when
    # this account's state was first written, not the host's age.
    stateVersion = "23.11";
    packages = with pkgs; [
      (bottles.override { removeWarningPopup = true; })
      veracrypt
      keepassxc
      btop-rocm
      iftop
      chromium
      tauon
      colordiff
      podman-compose
      #podman-tui
      mediainfo
      protonmail-desktop
      libreoffice-qt6-fresh
      obsidian
      discord
      webcord
      element-desktop
      jellyfin-desktop
      ffmpeg-hdr
      ripgrep
    ];
  };

  programs = {
    neovim = {
      enable = true;
      viAlias = true;
      vimAlias = true;
      defaultEditor = true;
      withPython3 = false;
      withRuby = false;
    };

    chromium = {
      enable = true;
      extensions = [
        "oboonakemofpalcgghocfoadofidjkkk" # KeePassXC-Browser
      ];
    };

    freetube = {
      enable = true;
      settings = {
        useRssFeeds = true;
        backendPreference = "local";
        enableSearchSuggestions = false;
        checkForBlogPosts = false;
        checkForUpdates = false;
        autoplayVideos = true;
        defaultVolume = 0.5;
        defaultPlayback = 2;
        defaultQuality = "1080";
        defaultTheatreMode = true;
        maxVideoPlaybackRate = true;
        videoPlaybackRateMouseScroll = true;
        videoVolumeMouseScroll = true;
        useSponsorBlock = true;
        sponsorBlockIntro = {
          color = "Orange";
          skip = "autoSkip";
        };
        sponsorBlockMusicOffTopic = {
          color = "Orange";
          skip = "autoSkip";
        };
        sponsorBlockOutro = {
          color = "Orange";
          skip = "showInSeekBar";
        };
        baseTheme = "dark";
        listType = "grid";
        disableSmoothScrolling = true;
        displayVideoPlayButton = false;
        commentAutoLoadEnabled = false;
        hideHeaderLogo = true;
        hidePopularVideos = true;
        hideTrendingVideos = true;
        hideActiveSubscriptions = true;
        enableScreenshot = true;
        screenshotFormat = "jpg";
        screenshotQuality = 85;
      };
    };
  };

  xdg = {
    enable = true;
    configFile."mimeapps.list".force = true;
    mimeApps = {
      enable = true;
      defaultApplications = {
        "text/html" = "librewolf.desktop";
        "x-scheme-handler/http" = "librewolf.desktop";
        "x-scheme-handler/https" = "librewolf.desktop";
        "x-scheme-handler/about" = "librewolf.desktop";
        "x-scheme-handler/unknown" = "librewolf.desktop";
      };
    };
  };
}
