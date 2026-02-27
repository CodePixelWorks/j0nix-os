{ config, lib, ... }:
let
  cfg = config.j0nix.desktop.fonts;
in
{
  options.j0nix.desktop.fonts.packages = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [ ];
    description = "Font packages installed system-wide for the desktop profile.";
  };

  config = {
    fonts.packages = cfg.packages;
    fonts.fontconfig.localConf = ''
      <!-- Bambu Studio asks for these HarmonyOS SC family names. -->
      <alias>
        <family>HarmonyOS_Sans_SC_Regular</family>
        <prefer>
          <family>Noto Sans CJK SC</family>
        </prefer>
      </alias>
      <alias>
        <family>HarmonyOS_Sans_SC_Bold</family>
        <prefer>
          <family>Noto Sans CJK SC</family>
        </prefer>
      </alias>
    '';
  };
}
