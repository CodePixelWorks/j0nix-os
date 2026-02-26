{ ... }:
{
  # Switch kernel presets by changing only this preset name.
  j0nix.desktop.kernel = {
    preset = "cachyos-x86_64-v4";

    modules = [
      # Help NVIDIA HDMI/DP audio endpoints appear reliably on some setups/TVs.
      "snd_hda_intel"
      "snd_hda_codec_hdmi"
    ];

    modprobeOptions = {
      # USB Bluetooth adapters/controllers can become unreliable after autosuspend.
      btusb.enable_autosuspend = 0;
    };
  };
}
