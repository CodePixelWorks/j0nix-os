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
      <?xml version="1.0"?>
      <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
      <fontconfig>
        <!-- Stable global defaults: keep UI fonts proportional even when many Nerd fonts are installed. -->
        <alias>
          <family>sans-serif</family>
          <prefer>
            <family>Cantarell</family>
            <family>Noto Sans</family>
            <family>Noto Sans CJK SC</family>
          </prefer>
        </alias>
        <alias>
          <family>serif</family>
          <prefer>
            <family>Noto Serif</family>
            <family>Noto Serif CJK SC</family>
          </prefer>
        </alias>
        <alias>
          <family>monospace</family>
          <prefer>
            <family>JetBrainsMono Nerd Font</family>
            <family>Noto Sans Mono</family>
          </prefer>
        </alias>
        <alias>
          <family>emoji</family>
          <prefer>
            <family>Noto Color Emoji</family>
          </prefer>
        </alias>

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
      </fontconfig>
    '';
  };
}
