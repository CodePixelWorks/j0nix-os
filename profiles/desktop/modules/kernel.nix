{ ... }:
{
  # Switch kernel presets by changing only this preset name.
  j0nix.desktop.kernel = {
    preset = "cachyos-x86_64-v4";

    modules = [
      # NVIDIA stack is loaded in initrd via nvidia-drivers.nix (includes nvidia_uvm for CUDA/Ollama).
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

    kernelParams = [
      # Avoid USB runtime autosuspend glitches (audio interfaces / HID devices re-enumerating).
      "usbcore.autosuspend=-1"
    ];

    # jc42 exposes the useful DIMM temperature sensors; ee1004 only reads SPD EEPROM
    # data and logs a boot-time page-select error on this board.
    blacklistedModules = [
      "ee1004"
    ];

    modprobeOptions = {
      # USB Bluetooth adapters/controllers can become unreliable after autosuspend.
      btusb.enable_autosuspend = 0;
      # Keep Intel Wi-Fi power saving disabled for better connection stability.
      iwlwifi.power_save = 0;
    };
  };
}
