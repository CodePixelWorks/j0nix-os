{
  # Profile-scoped system secret defaults. These are machine-facing and should
  # live close to the active profile instead of in the shared central config.
  defaultSopsFile = ../../secrets/hosts/Jonas-PC.yaml;

  age = {
    generateKey = true;
    keyFile = "/var/lib/sops-nix/key.txt";
    sshKeyPaths = [ ];
  };

  system = {
    tailscale-auth-key = {
      key = "tailscale/auth_key";
      owner = "root";
      group = "root";
      mode = "0400";
      restartUnits = [ "tailscaled.service" ];
    };
  };
}
