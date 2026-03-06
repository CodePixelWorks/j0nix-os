{ lib, settings, ... }:
let
  audio = settings.audio or { };
  audioBt = audio.bluetooth or { };
  defaultBluetoothCodecs = [
    "sbc"
    "sbc_xq"
    "aac"
    "aptx"
    "aptx_hd"
    "ldac"
  ];
in
{
  j0nix.desktop.audio = {
    backend = audio.backend or "pipewire";
    preventInterfaceSuspend = audio.preventInterfaceSuspend or true;
    bluetooth = {
      enableHiFiCodecs = audioBt.enableHiFiCodecs or true;
      enableMsbc = audioBt.enableMsbc or true;
      # Merge user/global codec preferences with desktop defaults and deduplicate.
      codecs = lib.unique ((audioBt.codecs or [ ]) ++ defaultBluetoothCodecs);
    };
  };
}
