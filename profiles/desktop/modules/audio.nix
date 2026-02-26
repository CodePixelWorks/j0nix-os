{ settings, ... }:
let
  audio = settings.audio or { };
  audioBt = audio.bluetooth or { };
in
{
  j0nix.desktop.audio = {
    backend = audio.backend or "pipewire";
    bluetooth = {
      enableHiFiCodecs = audioBt.enableHiFiCodecs or true;
      enableMsbc = audioBt.enableMsbc or true;
      codecs = audioBt.codecs or [
        "sbc"
        "sbc_xq"
        "aac"
        "aptx"
        "aptx_hd"
        "ldac"
      ];
    };
  };
}
