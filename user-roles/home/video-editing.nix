{ pkgs, ... }:
{
  j0nix.user.software.packages = with pkgs; [
    shotcut
    handbrake
    mkvtoolnix
    ffmpeg-full
    yt-dlp
    mediainfo
  ];
}
