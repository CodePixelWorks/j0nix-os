{ pkgs, ... }:
{
  # CPU Jitter Entropy for improved random number generation
  # This is particularly important for GPG key generation

  systemd.services.jitterentropy = {
    description = "CPU Jitter Entropy Daemon";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.jitterentropy-rngd}/bin/jitterentropy-rngd";
      Restart = "on-failure";
      RestartSec = 5;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
    };
  };

  # Kernel entropy tuning
  boot.kernel.sysctl = {
    "kernel.random.read_wakeup_threshold" = 64;
    "kernel.random.write_wakeup_threshold" = 128;
  };
}
