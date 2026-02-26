{ ... }:
{
  j0nix.desktop.boot = {
    tmp = {
      useTmpfs = false;
      tmpfsSize = "30%";
    };

    loader = {
      systemdBoot = {
        enable = true;
        configurationLimit = 12;
      };
      efi.canTouchEfiVariables = true;
    };

    # Hibernate via swapfile on / (ext4); resume_offset is configured separately.
    resumeDevice = "/dev/disk/by-uuid/28c5e755-f2df-4f57-af8a-36998a4a2f25";

    swapfile = {
      enable = true;
      path = "/swapfile";
      sizeMiB = 68 * 1024;
    };
  };
}
