{ pkgs, settings, ... }:
let
  nvidiaEnabled = ((settings.drivers or { }).nvidia or { }).enable or false;
  handbrakeWithHardwareCodecs =
    if nvidiaEnabled then
      pkgs.symlinkJoin {
        name = "handbrake-nvidia-${pkgs.handbrake.version}";
        paths = [ pkgs.handbrake ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          rm -f "$out/bin/HandBrakeCLI" "$out/bin/ghb"

          # HandBrake dynamically loads NVIDIA's codec libraries.  They live
          # outside its Nix closure on NixOS, so make NVENC available to both
          # the GUI and CLI without depending on the login-shell environment.
          makeWrapper ${pkgs.handbrake}/bin/HandBrakeCLI "$out/bin/HandBrakeCLI" \
            --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib \
            --set LIBVA_DRIVER_NAME nvidia \
            --set NVD_BACKEND direct
          makeWrapper ${pkgs.handbrake}/bin/ghb "$out/bin/ghb" \
            --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib \
            --set LIBVA_DRIVER_NAME nvidia \
            --set NVD_BACKEND direct
        '';
      }
    else
      pkgs.handbrake;
in
{
  imports = [ ../../user/programs/davinci-resolve ];

  j0nix.user.software.packages = with pkgs; [
    gpu-screen-recorder
    gpu-screen-recorder-gtk
    shotcut
    handbrakeWithHardwareCodecs
    mkvtoolnix
    ffmpeg-full
    yt-dlp
    mediainfo
  ];
}
