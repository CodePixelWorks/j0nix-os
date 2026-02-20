{ inputs, pkgs, lib, settings, ... }:
let
  users = settings.users or [ settings.username ];
  primaryUser = builtins.head users;
  useUWSM = (settings.hyprland or { }).useUWSM or true;
  hyprlandSessionName = if useUWSM then "hyprland-uwsm" else "hyprland";
  selectedDisplayManager = settings.displayManager or "sddm";
  useGreetd = selectedDisplayManager == "greetd";
  useSddm = selectedDisplayManager == "sddm";
  useGdm = selectedDisplayManager == "gdm";

  selectedGreetdGreeterRaw = settings.greetd.greeter or "tuigreet";
  selectedGreetdGreeter =
    if selectedGreetdGreeterRaw == "darkmaterialshell" then
      "dms-greeter"
    else
      selectedGreetdGreeterRaw;
  regreetCompositor = settings.greetd.regreetCompositor or "hyprland";

  useDankMaterialShell = useGreetd && selectedGreetdGreeter == "dms-greeter";
  useNvidia = ((settings.drivers or { }).nvidia or { }).enable or false;
  regreetPackage = if pkgs ? regreet then pkgs.regreet else pkgs.greetd.regreet;
  regreetHyprlandConfigPath = "/etc/regreet/hyprland.conf";
  hyprlandSessionPackage = (pkgs.writeTextDir "share/wayland-sessions/hyprland.desktop" ''
    [Desktop Entry]
    Name=Hyprland
    Comment=Hyprland Wayland compositor
    Exec=${if useUWSM then "${lib.getExe pkgs.uwsm} start hyprland-uwsm.desktop" else "Hyprland"}
    Type=Application
    DesktopNames=Hyprland
  '').overrideAttrs (old: {
    passthru = (old.passthru or { }) // {
      providedSessions = [ "hyprland" ];
    };
  });

  cursorTheme = "Bibata-Modern-Classic";
  cursorSize = 24;

  greetdEnvironments =
    [ "${hyprlandSessionName}.desktop" ]
    ++ lib.optional useUWSM "hyprland.desktop"
    ++ lib.optional (!useUWSM) "hyprland-uwsm.desktop"
    ++ lib.optional (builtins.elem "gnome" settings.wms) "gnome.desktop";

  regreetCommand =
    if regreetCompositor == "hyprland"
    then "start-hyprland -- -c ${regreetHyprlandConfigPath}"
    else "${lib.getExe pkgs.cage} -s -mlast -- ${lib.getExe regreetPackage}";
in {
  imports =
    [
      ./common/wayland.nix
    ]
    ++ lib.optional useDankMaterialShell inputs.dank-material-shell.nixosModules.greeter;

  services.displayManager.sddm = lib.mkIf useSddm {
    enable = true;
    wayland.enable = true;
    theme = "sddm-astronaut-theme";
    extraPackages = [ pkgs.sddm-astronaut ];
  };

  services.xserver.displayManager.gdm.enable = lib.mkIf useGdm true;

  services.displayManager.defaultSession = lib.mkIf useSddm hyprlandSessionName;
  services.displayManager.sessionPackages = [ hyprlandSessionPackage ];

  services.greetd = lib.mkIf useGreetd {
    enable = true;
    settings.default_session = lib.mkMerge [
      (lib.mkIf (selectedGreetdGreeter == "tuigreet") {
        user = primaryUser;
        command =
          if useUWSM
          then "${lib.getExe pkgs.tuigreet} --time --cmd '${lib.getExe pkgs.uwsm} start hyprland-uwsm.desktop'"
          else "${lib.getExe pkgs.tuigreet} --time --cmd Hyprland";
      })
      (lib.mkIf (selectedGreetdGreeter == "regreet") {
        user = "greeter";
        command = regreetCommand;
      })
      (lib.mkIf (selectedGreetdGreeter == "dms-greeter") {
        user = "greeter";
      })
    ];
  };

  programs.regreet.enable = useGreetd && selectedGreetdGreeter == "regreet";

  assertions = [
    {
      assertion = builtins.elem selectedDisplayManager [ "greetd" "sddm" "gdm" ];
      message = "settings.displayManager must be one of: greetd, sddm, gdm";
    }
    {
      assertion = (!useGreetd) || builtins.elem selectedGreetdGreeter [ "tuigreet" "regreet" "dms-greeter" ];
      message = "settings.greetd.greeter must be one of: tuigreet, regreet, dms-greeter (legacy alias: darkmaterialshell)";
    }
    {
      assertion = (!useGreetd) || builtins.elem regreetCompositor [ "cage" "hyprland" ];
      message = "settings.greetd.regreetCompositor must be one of: cage, hyprland";
    }
  ];

  environment.systemPackages = with pkgs; [
    brightnessctl
    bibata-cursors
  ];

  environment.sessionVariables = {
    XCURSOR_THEME = cursorTheme;
    XCURSOR_SIZE = toString cursorSize;
  } // lib.optionalAttrs useNvidia {
    NIXOS_OZONE_WL = "1";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    LIBVA_DRIVER_NAME = "nvidia";
  };

  environment.etc."greetd/environments" = lib.mkIf useGreetd {
    text = (lib.concatStringsSep "\n" greetdEnvironments) + "\n";
    mode = "0444";
  };

  environment.etc."regreet/hyprland.conf" = lib.mkIf (useGreetd && selectedGreetdGreeter == "regreet" && regreetCompositor == "hyprland") {
    text = ''
      misc {
        disable_hyprland_logo = true
        disable_splash_rendering = true
        disable_hyprland_guiutils_check = true
      }

      env = XCURSOR_THEME,${cursorTheme}
      env = XCURSOR_SIZE,${toString cursorSize}
    '';
    mode = "0444";
  };

  programs.hyprland = {
    enable = true;
    withUWSM = useUWSM;
    xwayland.enable = true;
    package = pkgs.hyprland;
    portalPackage = pkgs.xdg-desktop-portal-hyprland;
  };

  nix.settings = {
    substituters = [ "https://hyprland.cachix.org" ];
    trusted-public-keys = [ "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" ];
  };

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    config = {
      hyprland.default = [ "hyprland" ];
    };
  };
} // lib.optionalAttrs useDankMaterialShell {
  programs.dank-material-shell.greeter = {
    enable = true;
    compositor.name = "hyprland";
  };
}
