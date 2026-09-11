{
  lib,
  nms-patcher,
  python3,
  writeShellApplication,
}:
writeShellApplication {
  name = "game-mods";
  runtimeInputs = [ nms-patcher ];
  text = ''
    exec ${python3}/bin/python ${./game-mods.py} "$@"
  '';

  meta = {
    description = "Declarative Steam game mod target manager";
    homepage = "https://github.com/j0nix-os/j0nix-os";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
