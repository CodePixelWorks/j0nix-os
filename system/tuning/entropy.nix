{ pkgs, ... }:
{
  # =============================================================================
  # Entropy/Random Number Generation for GPG key generation
  # =============================================================================
  # Multiple entropy sources ensure fast and secure key generation

  # 1. jitterentropy - CPU timing jitter entropy (modern, low overhead)
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

  # 2. rng-tools - Provides /dev/hwrng support and additional entropy
  #    Fallback for systems without jitterentropy or hardware RNG
  systemd.services.rngd = {
    description = "Entropy RNG Daemon";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    serviceConfig = {
      Type = "simple";
      # Use /dev/urandom as fallback source (safe for seeding)
      ExecStart = "${pkgs.rng-tools}/bin/rngd -f -x jitterentropy";
      Restart = "on-failure";
      RestartSec = 5;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
    };
  };

  # 3. haveged - Hardware-generated entropy based on CPU cache timing
  #    Provides fast, continuous entropy for desktop systems
  systemd.services.haveged = {
    description = "Hardware Volatile Entropy Gathering and Expansion Daemon";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    serviceConfig = {
      Type = "simple";
      # -w: set entropy wakeup threshold (1024 is good for desktop)
      # -v: verbose (optional, remove for production)
      ExecStart = "${pkgs.haveged}/bin/haveged -w 1024";
      Restart = "on-failure";
      RestartSec = 5;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
    };
  };

  # Kernel entropy pool tuning for better throughput
  boot.kernel.sysctl = {
    # Lower values = less CPU wakeups, better performance
    # Higher values = more responsive, more CPU usage
    "kernel.random.read_wakeup_threshold" = 64;
    "kernel.random.write_wakeup_threshold" = 128;
    # Entropy quality settings
    "kernel.random.entropy_read_sleep_ms" = 0;
  };
}
