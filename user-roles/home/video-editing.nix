{ pkgs, ... }:
{
  j0nix.user.software.packages = with pkgs; [
    kdenlive
    handbrake
    mkvtoolnix
    ffmpeg-full
    yt-dlp
    mediainfo
  ];
}
