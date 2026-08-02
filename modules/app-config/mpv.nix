{ config, inputs, ... }:
let
  mpvModule =
    { pkgs, ... }:
    let
      # Keep the package-set boundary explicit. These alpkgs outputs are leaf
      # scripts/shaders; MPV and its compiled dependencies come from the
      # consumer's pkgs.
      alpkgs = inputs.alpkgs.packages.${pkgs.stdenv.hostPlatform.system};
      modernx = pkgs.mpvScripts.modernx-zydezu;
      fontsConf = pkgs.makeFontsConf {
        includes = [ ];
        fontDirectories = [
          "${modernx}/share/fonts"
          "${pkgs.noto-fonts}/share/fonts"
          "${pkgs.dejavu_fonts}/share/fonts"
        ];
      };
      shaders = {
        default = "${pkgs.mpv-shim-default-shaders}/share/mpv-shim-default-shaders/shaders";
        art = "${alpkgs.ArtCNN}/share/ArtCNN/GLSL";
        super = "${alpkgs.SSimSuperRes}/share/shaders/SSimSuperRes.glsl";
      };
      scriptPath = package: "${package}/share/mpv/scripts/${package.scriptName}";
    in
    {
      imports = [ inputs.nix-wrapper-modules.wrapperModules.mpv ];

      package = pkgs.mpv.override {
        extraMakeWrapperArgs = [
          "--set"
          "FONTCONFIG_FILE"
          (toString fontsConf)
        ];
        mpv-unwrapped = pkgs.mpv-unwrapped.override { ffmpeg = pkgs.ffmpeg-full; };
      };

      "mpv.conf".content = ''
          af=lavfi=[loudnorm=I=-16:TP=-3:LRA=4]
          audio-channels=stereo
          audio-file-auto=fuzzy
          audio-pitch-correction=yes
          audio-stream-silence=no
          blend-subtitles=yes
          border=no
          cache=yes
          cache-on-disk=no
          correct-downscaling=yes
          cscale=ewa_lanczos
          cscale-antiring=0
          deband=no
          deband-grain=5
          deband-iterations=3
          deband-range=16
          deband-threshold=20
          demuxer-max-back-bytes=1GiB
          demuxer-max-bytes=1GiB
          demuxer-mkv-subtitle-preroll
          dither=error-diffusion
          dither-depth=auto
          dscale=mitchell
          dscale-antiring=0.600000
          embeddedfonts=yes
          fullscreen=no
          glsl-shaders-clr
          gpu-api=vulkan
          hdr-compute-peak=yes
          hdr-contrast-recovery=0.300000
          hdr-peak-percentile=99.995000
          hwdec=auto-safe
          interpolation=no
          keep-open=yes
          linear-downscaling=no
          msg-color=yes
          msg-module=yes
          no-input-default-bindings
          no-resume-playback
          osc=no
          osd-font=Noto Sans
          reset-on-next-file=audio-delay,mute,pause,speed,sub-delay,video-aspect-override,video-pan-x,video-pan-y,video-rotate,video-zoom
          scale=ewa_hanning
          scale-antiring=0.600000
          scale-radius=3.238315
          screenshot-dir=~/Pictures/mpv
          screenshot-format=jpg
          screenshot-high-bit-depth=yes
          screenshot-jpeg-quality=95
          screenshot-jxl-distance=0.1
          screenshot-jxl-effort=8
          screenshot-png-compression=8
          screenshot-tag-colorspace=yes
          screenshot-template="T%wM%wS-%#01n-%F [%P]"
          sid=auto
          sigmoid-upscaling=yes
          sub-ass-scale-with-window=no
          sub-ass-use-video-data=all
          sub-auto=fuzzy
          sub-file-paths-append=ass
          sub-file-paths-append=srt
          sub-file-paths-append=sub
          sub-file-paths-append=subs
          sub-file-paths-append=subtitles
          sub-file-paths-append=en
          sub-file-paths-append=eng
          sub-file-paths-append=english
          sub-fix-timing=no
          target-colorspace-hint=yes
          target-peak=auto
          target-prim=auto
          target-trc=auto
          temporal-dither=yes
          title=''${filename} - mpv
          tone-mapping=mobius
          vd-lavc-dr=yes
          video-sync=display-resample
          vo=gpu-next
          volume=50
          volume-max=150
          vulkan-async-compute=yes
          vulkan-async-transfer=yes
          ytdl-format=bestvideo[height<=1080]+bestaudio/best[height<=1080]

          [anime4k_a]
          glsl-shaders=${shaders.default}/Anime4K_Clamp_Highlights.glsl
          glsl-shaders-append=${shaders.default}/Anime4K_Restore_CNN_VL.glsl
          glsl-shaders-append=${shaders.default}/Anime4K_Upscale_CNN_x2_VL.glsl
          glsl-shaders-append=${shaders.default}/Anime4K_AutoDownscalePre_x2.glsl
          glsl-shaders-append=${shaders.default}/Anime4K_AutoDownscalePre_x4.glsl
          glsl-shaders-append=${shaders.default}/Anime4K_Upscale_CNN_x2_M.glsl

          [anime4k_b]
          glsl-shaders=${shaders.default}/Anime4K_Clamp_Highlights.glsl
          glsl-shaders-append=${shaders.default}/CAS-scaled.glsl
          glsl-shaders-append=${shaders.default}/Anime4K_Restore_CNN_Soft_VL.glsl
          glsl-shaders-append=${shaders.default}/Anime4K_Upscale_CNN_x2_VL.glsl
          glsl-shaders-append=${shaders.default}/Anime4K_AutoDownscalePre_x2.glsl
          glsl-shaders-append=${shaders.default}/Anime4K_AutoDownscalePre_x4.glsl
          glsl-shaders-append=${shaders.default}/Anime4K_Upscale_CNN_x2_M.glsl

          [anime4k_c]
          glsl-shaders=${shaders.default}/Anime4K_Clamp_Highlights.glsl
          glsl-shaders-append=${shaders.default}/Anime4K_Upscale_Denoise_CNN_x2_VL.glsl
          glsl-shaders-append=${shaders.default}/Anime4K_AutoDownscalePre_x2.glsl
          glsl-shaders-append=${shaders.default}/Anime4K_AutoDownscalePre_x4.glsl
          glsl-shaders-append=${shaders.default}/Anime4K_Upscale_CNN_x2_M.glsl

          [art]
          cscale=mitchell
          dscale=mitchell
          glsl-shaders=${shaders.art}/ArtCNN_C4F32.glsl

          [artdn]
          cscale=mitchell
          dscale=mitchell
          glsl-shaders=${shaders.art}/ArtCNN_C4F32_DN.glsl

          [artds]
          cscale=mitchell
          dscale=mitchell
          glsl-shaders=${shaders.art}/ArtCNN_C4F32_DS.glsl

          [fsrcnnx]
          cscale=mitchell
          dscale=mitchell
          glsl-shaders=${shaders.default}/FSRCNNX_x2_16-0-4-1.glsl
          glsl-shaders-append=${shaders.default}/SSimDownscaler.glsl
          glsl-shaders-append=${shaders.default}/KrigBilateral.glsl

          [generic]
          cscale=ewa_lanczos
          dscale=mitchell
          scale=ewa_hanning

          [super]
          cscale=ewa_lanczos
          dscale=mitchell
          glsl-shaders=${shaders.super}
          scale=ewa_hanning
      '';

      "mpv.input".content = ''
          , add chapter -1
          - add audio-delay -0.05
          . add chapter 1
          1 add contrast -1
          2 add contrast 1
          3 add brightness -1
          4 add brightness 1
          5 add gamma -1
          6 add gamma 1
          7 add saturation -1
          8 add saturation 1
          = add audio-delay +0.05
          CLOSE_WIN quit
          CTRL+0 show-text "Profile: hanning (default)"; no-osd change-list glsl-shaders clr all; apply-profile generic
          CTRL+1 show-text "Profile: superRes"; no-osd apply-profile super
          CTRL+2 show-text "Profile: general purpose [FSRCNNX16/SSimDown/KrigBilat]"; no-osd apply-profile fsrcnnx
          CTRL+3 show-text "Profile: anime [ArtCNN_C4F32]"; no-osd apply-profile art
          CTRL+4 show-text "Profile: anime denoise soft [ArtCNN_C4F32_DN]"; no-osd apply-profile artdn
          CTRL+5 show-text "Profile: anime denoise sharp [ArtCNN_C4F32_DS]"; no-osd apply-profile artds
          CTRL+6 show-text "Profile: Anime4K A (HQ) - For Very Blurry/Compressed"; no-osd apply-profile anime4k_a
          CTRL+7 show-text "Profile: Anime4K B (HQ) - For Blurry/Ringing"; no-osd apply-profile anime4k_b
          CTRL+8 show-text "Profile: Anime4K C (HQ) - For Crisp/Sharp"; no-osd apply-profile anime4k_c
          CTRL+LEFT seek -0.01 keyframes
          CTRL+RIGHT seek +0.001 keyframes
          CTRL+WHEEL_DOWN add video-zoom -0.1
          CTRL+WHEEL_UP add video-zoom  0.1
          CTRL+c script-message-to copyPasteTime copyTime
          CTRL+s screenshot
          CTRL+v script-message-to copyPasteTime pasteTime
          DOWN add volume -1
          ESC set fullscreen no
          F3 script-binding stats/display-stats-toggle
          LEFT seek -5
          MBTN_BACK add chapter -1
          MBTN_FORWARD add chapter 1
          MBTN_LEFT ignore
          MBTN_LEFT_DBL cycle fullscreen
          MBTN_RIGHT cycle pause
          RIGHT seek  5
          SHIFT+DOWN add volume -10
          SHIFT+LEFT frame-back-step
          SHIFT+RIGHT frame-step
          SHIFT+UP add volume 10
          SHIFT+c script-message-to copyPasteTime copyFrame
          SHIFT+s screenshot video
          SHIFT+t cycle ontop
          SPACE cycle pause
          UP add volume 1
          WHEEL_DOWN add volume -2
          WHEEL_LEFT seek -10
          WHEEL_RIGHT seek 10
          WHEEL_UP add volume 2
          [ add sub-delay -0.05
          ] add sub-delay +0.05
          ` script-binding console/enable
          a cycle audio
          b cycle deband
          d cycle deinterlace
          e cycle edition
          f cycle fullscreen
          h script-binding videoclip-menu-open
          j script-message cycle-commands "set screenshot-format jxl;show-text \"screenshot-format: jxl (visually lossless)\"" "set screenshot-format jpg;show-text \"screenshot-format: jpg\"" "set screenshot-format png;show-text \"screenshot-format: png (lossless)\""
          l script-message cycle-commands "set af \"lavfi=[loudnorm=I=-16:TP=-3:LRA=4]\";show-text \"Normalized Loudness\"" "set af \"\";show-text \"Unnormalized Loudness\""
          m cycle mute
          p show-progress
          q script-binding quality_menu/video_formats_toggle
          s cycle sub
          t script-message-to seek_to toggle-seeker
          v cycle video
          { add speed -0.25
          } add speed 0.25
      '';

      configDir."script-opts/modernx.conf".content = ''
        compact_mode=yes
        info_button=yes
      '';

      script = builtins.listToAttrs (map (package: {
        name = package.scriptName;
        value.path = scriptPath package;
      }) [
        pkgs.mpvScripts.seekTo
        modernx
        pkgs.mpvScripts.thumbfast
        pkgs.mpvScripts.sponsorblock
        pkgs.mpvScripts.quality-menu
        pkgs.mpvScripts.quack
        pkgs.mpvScripts.videoclip
        alpkgs.mpv-cycleCommands
        alpkgs.mpv-clipboard
        alpkgs.mpv-copyPasteTime
      ]);
    };
in
{
  flake.wrappers = {
    mpv = mpvModule;
    mpv-software = {
      imports = [ config.flake.wrapperModules.mpv ];
      binName = "mpv-software";
      drv.meta.mainProgram = "mpv-software";
      filesToExclude = [ "share/applications/*.desktop" ];
      flags = {
        "--hwdec" = "no";
        "--gpu-api" = "opengl";
        "--vulkan-async-compute" = "no";
        "--vulkan-async-transfer" = "no";
      };
    };
  };
}
