{
  lib,
  nexus-collection-dl,
  python3,
  writeShellApplication,
}:
writeShellApplication {
  name = "nms-patcher";
  runtimeInputs = [ nexus-collection-dl ];
  text = ''
    exec ${python3}/bin/python ${./nms-patcher.py} "$@"
  '';

  meta = {
    description = "Safe No Man's Sky PAK mod deployment tool";
    homepage = "https://github.com/j0nix-os/j0nix-os";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
