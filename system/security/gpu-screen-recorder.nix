{ lib, pkgs, ... }:
lib.mkIf (pkgs ? gpu-screen-recorder) {
  security.wrappers.gsr-kms-server = {
    source = "${pkgs.gpu-screen-recorder}/bin/gsr-kms-server";
    owner = "root";
    group = "root";
    permissions = "u+rx,g+rx,o+rx";
    capabilities = "cap_sys_admin+ep";
  };
}
