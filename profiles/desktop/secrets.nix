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
    syncthing-gui-password = {
      key = "syncthing/gui_password";
      owner = "jonas";
      group = "users";
      mode = "0400";
    };
  };
}
