# Driver Modules

Driver stack controlled by `settings.drivers.*`.

## Files

- `default.nix`: imports driver modules and validates combinations
- `amd-drivers.nix`: AMD GPU setup
- `intel-drivers.nix`: Intel media/VA packages
- `nvidia-drivers.nix`: NVIDIA driver + graphics stack
- `nvidia-prime-drivers.nix`: PRIME offload settings
- `vm-guest-services.nix`: guest integrations (QEMU/SPICE/VMware)
- `local-hardware-clock.nix`: RTC local-time toggle
- `support.nix`: support drivers and host-specific hardware stabilizers (e.g. IT87, USB keep-awake rules)

## Notes

- Bare-metal NVIDIA should keep `settings.drivers.vmGuestServices.enable = false`.
- PRIME requires both Intel and NVIDIA enabled.
- NVIDIA package selection is controlled through `settings.drivers.nvidia.package`.
- `settings.drivers.nvidia.expectedVersion` can pin the selected branch to an exact evaluated version.
- LACT can be enabled through `settings.drivers.nvidia.lact.enable`.
