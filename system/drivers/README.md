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
- `settings.drivers.nvidia.powerManagement.enable` toggles the NVIDIA suspend/resume helper services and preserved video memory path.
- `settings.drivers.nvidia.powerManagement.finegrained` should stay off unless a host specifically needs the finer runtime PM behavior.
- LACT can be enabled through `settings.drivers.nvidia.lact.enable`.
- The NVIDIA module also seeds the display stack into the initrd so Plymouth can light up connected displays earlier during boot.
- The matching NVIDIA firmware derivation is added to `hardware.firmware` so early initrd driver loads can still find the GSP blobs they request.
