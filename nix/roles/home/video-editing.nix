{ pkgs, ... }:
{
  j0nix.user.software.packages = with pkgs; [
    davinci-resolve
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
