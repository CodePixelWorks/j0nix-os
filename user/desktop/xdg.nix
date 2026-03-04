{ config, lib, settings, ... }:
let
  configuredFileManagersRaw =
    settings.fileManagers
    or (lib.optional ((settings.preferredFileManager or null) != null) settings.preferredFileManager);
  configuredFileManagers =
    lib.unique (if configuredFileManagersRaw != [ ] then configuredFileManagersRaw else [ "nautilus" ]);
  preferredFileManager =
    settings.preferredFileManager
    or (if configuredFileManagers != [ ] then builtins.head configuredFileManagers else "nautilus");
  fileManagerDesktopId = name:
    if name == "nautilus" then
      "org.gnome.Nautilus.desktop"
    else if name == "nemo" then
      "nemo.desktop"
    else if name == "dolphin" then
      "org.kde.dolphin.desktop"
    else if name == "thunar" then
      "thunar.desktop"
    else
      null;
  preferredFileManagerDesktopId = fileManagerDesktopId preferredFileManager;
in
{
  xdg.enable = true;
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http" = [ "chromium.desktop" ];
      "x-scheme-handler/https" = [ "chromium.desktop" ];
      "text/html" = [ "chromium.desktop" ];
    } // lib.optionalAttrs (preferredFileManagerDesktopId != null) {
      "inode/directory" = [ preferredFileManagerDesktopId ];
      "x-scheme-handler/file" = [ preferredFileManagerDesktopId ];
    };
  };
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    music = "${config.home.homeDirectory}/Media/Music";
    videos = "${config.home.homeDirectory}/Media/Videos";
    pictures = "${config.home.homeDirectory}/Media/Pictures";
    download = "${config.home.homeDirectory}/Downloads";
    documents = "${config.home.homeDirectory}/Documents";
    templates = null;
    desktop = null;
    publicShare = null;
    extraConfig = {
      DOTFILES = settings.dotfilesDir;
      BOOK = "${config.home.homeDirectory}/Media/Books";
    };
  };

  assertions = [
    {
      assertion = builtins.elem preferredFileManager configuredFileManagers;
      message = "preferredFileManager must also be included in the effective per-user fileManagers list";
    }
    {
      assertion = lib.all (name: builtins.elem name [ "nautilus" "nemo" "dolphin" "thunar" ]) configuredFileManagers;
      message = "The effective per-user fileManagers list may only contain: nautilus, nemo, dolphin, thunar";
    }
  ];
}
