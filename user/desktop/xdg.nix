{ config, lib, pkgs, settings, ... }:
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
  # Krita ships many mime-specific launcher files (krita_png.desktop, ...).
  # Hide those helpers from "Open With" and keep only org.kde.krita.desktop visible.
  kritaMimeHelperDesktopEntries = [
    "krita_brush"
    "krita_csv"
    "krita_exr"
    "krita_gif"
    "krita_heif"
    "krita_heightmap"
    "krita_jp2"
    "krita_jpeg"
    "krita_jxl"
    "krita_kra"
    "krita_krz"
    "krita_ora"
    "krita_pdf"
    "krita_png"
    "krita_psd"
    "krita_qimageio"
    "krita_spriter"
    "krita_svg"
    "krita_tga"
    "krita_tiff"
    "krita_webp"
    "krita_xcf"
  ];
  kritaMimeHelperOverrides = lib.genAttrs kritaMimeHelperDesktopEntries (entry: {
    name = "Krita Internal Handler (${entry})";
    noDisplay = true;
    terminal = false;
    type = "Application";
    exec = "false";
  });
  flatpakRefInstallScript = pkgs.writeShellScriptBin "flatpakref-install" ''
    set -eu

    if [ "$#" -lt 1 ]; then
      echo "usage: flatpakref-install <url-or-file>" >&2
      exit 2
    fi

    target="$1"
    case "$target" in
      flatpak+https://*)
        target="https://''${target#flatpak+https://}"
        ;;
      flatpak+http://*)
        target="http://''${target#flatpak+http://}"
        ;;
    esac

    status=0
    ${pkgs.flatpak}/bin/flatpak install --user --from "$target" || status=$?
    printf '\nPress Enter to close...'
    read -r _ || true
    exit "$status"
  '';
  flatpakRefHandlerScript = pkgs.writeShellScriptBin "flatpakref-handler" ''
    set -eu
    exec ${lib.getExe pkgs.xdg-terminal-exec} ${lib.getExe flatpakRefInstallScript} "$@"
  '';
in
{
  xdg.enable = true;
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http" = [ "chromium.desktop" ];
      "x-scheme-handler/https" = [ "chromium.desktop" ];
      "x-scheme-handler/flatpak+http" = [ "j0nix-flatpakref-handler.desktop" ];
      "x-scheme-handler/flatpak+https" = [ "j0nix-flatpakref-handler.desktop" ];
      "text/html" = [ "chromium.desktop" ];
      "application/vnd.flatpak" = [ "j0nix-flatpakref-handler.desktop" ];
      "application/vnd.flatpak.ref" = [ "j0nix-flatpakref-handler.desktop" ];
      "application/vnd.flatpak.repo" = [ "j0nix-flatpakref-handler.desktop" ];
      "application/pdf" = [
        "org.kde.okular.desktop"
        "okularApplication_pdf.desktop"
      ];
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
  xdg.desktopEntries = kritaMimeHelperOverrides // {
    j0nix-flatpakref-handler = {
      name = "Flatpak Ref Installer";
      noDisplay = true;
      terminal = false;
      type = "Application";
      exec = "${lib.getExe flatpakRefHandlerScript} %u";
      mimeType = [
        "x-scheme-handler/flatpak+http"
        "x-scheme-handler/flatpak+https"
        "application/vnd.flatpak"
        "application/vnd.flatpak.ref"
        "application/vnd.flatpak.repo"
      ];
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
