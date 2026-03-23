{
  lib,
  pkgs,
  settings,
  ...
}:
let
  syncthingCfg = (settings.programs or { }).syncthing or { };
  syncthingEnabled = syncthingCfg.enable or false;
  enableUdiskieAutomount = true;

  configuredFileManagersRaw =
    settings.fileManagers
      or (lib.optional ((settings.preferredFileManager or null) != null) settings.preferredFileManager);
  configuredFileManagers = lib.unique (
    if configuredFileManagersRaw != [ ] then configuredFileManagersRaw else [ "nautilus" ]
  );
  fileManagerPackage =
    name:
    if name == "nautilus" then
      pkgs.nautilus
    else if name == "nemo" then
      pkgs.nemo
    else if name == "dolphin" then
      if (pkgs ? kdePackages) && (pkgs.kdePackages ? dolphin) then pkgs.kdePackages.dolphin else null
    else if name == "thunar" then
      if (pkgs ? xfce) && (pkgs.xfce ? thunar) then pkgs.xfce.thunar else null
    else
      null;
  fileManagerPackages = lib.filter (pkg: pkg != null) (map fileManagerPackage configuredFileManagers);

  preferredTerminalRaw = settings.preferredTerminal or null;
  terminalPackage =
    name:
    if name == "kitty" then
      pkgs.kitty
    else if name == "foot" then
      pkgs.foot
    else if
      builtins.elem name [
        "kgx"
        "gnome-console"
        "gnome console"
      ]
    then
      if pkgs ? gnome-console then pkgs.gnome-console else null
    else
      null;
  preferredTerminalPackage =
    if preferredTerminalRaw != null then terminalPackage preferredTerminalRaw else null;

  iconThemeCfg = settings.iconTheme or { };
  iconThemeEnabled = iconThemeCfg.enable or true;
  iconThemePackageKey = iconThemeCfg.package or "papirus";
  iconThemePackage =
    if iconThemePackageKey == "papirus" then
      pkgs.papirus-icon-theme
    else if iconThemePackageKey == "colloid" then
      if pkgs ? "colloid-icon-theme" then pkgs."colloid-icon-theme" else null
    else if iconThemePackageKey == "adwaita" then
      pkgs.adwaita-icon-theme
    else if iconThemePackageKey == "breeze" then
      if (pkgs ? kdePackages) && (pkgs.kdePackages ? breeze-icons) then
        pkgs.kdePackages.breeze-icons
      else if pkgs ? breeze-icons then
        pkgs.breeze-icons
      else
        null
    else
      null;
  iconThemeFallbackPackages = with pkgs; [
    hicolor-icon-theme
    adwaita-icon-theme
  ];
  obsidianWayland = pkgs.symlinkJoin {
    name = "obsidian-wayland";
    paths = [ pkgs.obsidian ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm -f "$out/bin/obsidian"
      makeWrapper ${pkgs.obsidian}/bin/obsidian "$out/bin/obsidian" \
        --add-flags "--ozone-platform-hint=auto"
    '';
  };
in
{
  j0nix.user.software.packages =
    (with pkgs; [
      kitty
      gh
      starship
      obs-studio
      qbittorrent
      telegram-desktop
      nextcloud-client
      drawio
      simplescreenrecorder
      gpu-screen-recorder
      gpu-screen-recorder-gtk
      krita
      blender
      gimp
      naps2
      mpv
      libreoffice-fresh
      gcc
      gnumake
      nodejs
      python3
      cargo
      rustc
      openvpn
      p7zip
      android-tools
      xdg-utils
    ])
    ++ [ obsidianWayland ]
    ++ fileManagerPackages
    ++ lib.optionals (preferredTerminalPackage != null) [ preferredTerminalPackage ]
    ++ lib.optionals enableUdiskieAutomount [ pkgs.udiskie ]
    ++ lib.optionals syncthingEnabled [ pkgs.syncthing ]
    ++ lib.optionals (iconThemeEnabled && iconThemePackage != null) (
      [ iconThemePackage ] ++ iconThemeFallbackPackages
    );
}
