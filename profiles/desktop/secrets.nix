{
  # Profile-scoped system secret defaults. These are machine-facing and should
  # live close to the active profile instead of in the shared central config.
  defaultSopsFile = null;

  age = {
    generateKey = true;
    keyFile = "/var/lib/sops-nix/key.txt";
    sshKeyPaths = [ ];
  };

  system = { };
}
