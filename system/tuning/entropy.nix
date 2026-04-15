{ ... }:
{
  # Entropy source for improved random number generation
  # jitterentropy: Uses CPU timing jitter as entropy source (modern, secure)
  # kernel.random.read_wakeup_threshold: Reduce wakeups for better throughput
  # kernel.random.write_wakeup_threshold: Threshold for blocking writes

  services.jitterentropy = {
    enable = true;
  };

  # Ensure kernel entropy pool is well-seeded
  boot.kernel.sysctl = {
    "kernel.random.read_wakeup_threshold" = 64;
    "kernel.random.write_wakeup_threshold" = 128;
  };
}
