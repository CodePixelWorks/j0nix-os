{
  lib,
  pkgs,
  settings,
  ...
}:
let
  inputMethodCfg = settings.inputMethod or { };
  enabled = inputMethodCfg.enable or true;
  chineseEnabled = inputMethodCfg.chinese or true;
  engine = inputMethodCfg.engine or "rime";
  useFcitx5 = enabled && chineseEnabled && engine == "rime";
  fcitxProfileText = ''
    [Groups/0]
    # Group Name
    Name="Default"
    # Layout
    Default Layout=cn
    # Default Input Method
    DefaultIM=rime

    [Groups/0/Items/0]
    # Name
    Name=keyboard-cn
    # Layout
    Layout=

    [Groups/0/Items/1]
    # Name
    Name=rime
    # Layout
    Layout=

    [GroupOrder]
    0="Default"
  '';
in
{
  j0nix.user.software.packages = lib.optionals useFcitx5 (
    [
      pkgs.fcitx5
      pkgs.fcitx5-rime
      pkgs.fcitx5-gtk
      pkgs.qt6Packages.fcitx5-qt
      pkgs.qt6Packages.fcitx5-configtool
    ]
  );

  home.sessionVariables = lib.mkIf useFcitx5 {
    XMODIFIERS = "@im=fcitx";
    QT_IM_MODULE = "fcitx";
    SDL_IM_MODULE = "fcitx";
    GLFW_IM_MODULE = "ibus";
  };

  xdg.configFile."fcitx5/profile" = lib.mkIf useFcitx5 {
    text = fcitxProfileText;
  };

  systemd.user.services.fcitx5 = lib.mkIf useFcitx5 {
    Unit = {
      Description = "Fcitx 5 input method daemon";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${pkgs.fcitx5}/bin/fcitx5 -dr";
      Restart = "on-failure";
      RestartSec = 2;
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };

  assertions = [
    {
      assertion = builtins.elem engine [ "rime" ];
      message = "settings.inputMethod.engine must be \"rime\"";
    }
  ];
}
