{ pkgs, ... }:
{
  j0nix.user.software.packages = with pkgs; [
    gpu-screen-recorder
    gpu-screen-recorder-gtk
    shotcut
    handbrake
    mkvtoolnix
    ffmpeg-full
    yt-dlp
    mediainfo
  ];
}
