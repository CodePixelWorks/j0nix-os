{ ... }:
{
  # Switch kernel presets by changing only this preset name.
  j0nix.desktop.kernel = {
    preset = "cachyos-x86_64-v4";

    modules = [
      # Help NVIDIA HDMI/DP audio endpoints appear reliably on some setups/TVs.
      "snd_hda_intel"
      "snd_hda_codec_hdmi"
      # Expose board/SMBus temperature sensors for lm_sensors on this AMD desktop.
      "jc42"
      "lm75"
      # KVM/QEMU host acceleration and virtio fast paths on AMD systems.
      "kvm_amd"
      "vhost"
      "vhost_net"
      "vhost_vsock"
    ];

    modprobeOptions = {
      # USB Bluetooth adapters/controllers can become unreliable after autosuspend.
      btusb.enable_autosuspend = 0;
      # Improve Intel Wi-Fi 6 association by disabling aggressive power saving.
      iwlwifi.power_save = 2;
    };
  };
}
