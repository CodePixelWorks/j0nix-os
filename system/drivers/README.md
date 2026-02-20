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

## Notes

- Bare-metal NVIDIA should keep `settings.drivers.vmGuestServices.enable = false`.
- PRIME requires both Intel and NVIDIA enabled.
