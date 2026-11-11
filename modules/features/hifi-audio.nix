/**
  Enables the standard PipeWire audio stack with ALSA, 32-bit ALSA, PulseAudio
  compatibility, and realtime scheduling support.
*/
{
  flake.modules.nixos.hifi-audio = {
    security.rtkit.enable = true;

    services.pipewire = {
      enable = true;
      alsa = {
        enable = true;
        support32Bit = true;
      };
      pulse.enable = true;
      # TODO(audio): reduce everyday audio latency with modest PipeWire buffer tuning, validated under normal load without crackling.
    };
  };
}
