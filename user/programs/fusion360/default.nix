{ lib, pkgs, settings, ... }:
let
  programsCfg = settings.programs or { };
  fusionCfg = programsCfg.fusion360 or { };
  installerCfg = fusionCfg.protonInstaller or { };
  enabled = installerCfg.enable or true;
  protonVersion = installerCfg.protonVersion or "GE-Proton10-30";
  installerUrl =
    installerCfg.installerUrl
    or "https://raw.githubusercontent.com/Lolig4/Autodesk-Fusion-360-for-Linux/main/files/setup/autodesk_fusion_installer_x86-64.sh";
  cleanupLegacyDesktop = installerCfg.cleanupLegacyDesktop or true;

  fusion360ProtonSetup = pkgs.writeShellApplication {
    name = "fusion360-proton-setup";
    runtimeInputs = with pkgs; [
      curl
      coreutils
      gnugrep
    ];
    text = ''
      set -euo pipefail

      PROTON_VERSION="''${FUSION360_PROTON_VERSION:-${protonVersion}}"
      INSTALLER_URL="''${FUSION360_INSTALLER_URL:-${installerUrl}}"
      CACHE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/j0nix-os/fusion360"
      INSTALLER_PATH="$CACHE_DIR/autodesk_fusion_installer_x86-64.sh"

      mkdir -p "$CACHE_DIR"
      curl -L "$INSTALLER_URL" -o "$INSTALLER_PATH"
      chmod +x "$INSTALLER_PATH"

      # Patch known upstream shell script regressions (observed in current community script revisions).
      # 1) Snap check should be optional on systems without snap installed.
      # 2) Broken function declaration causes a syntax error near line ~742.
      sed -i \
        -e 's|if snap list |if command -v snap >/dev/null 2>\&1 \&\& snap list |' \
        -e 's/^is_snap_firefox_installed {$/is_snap_firefox_installed() {/' \
        "$INSTALLER_PATH"

      ${
        if cleanupLegacyDesktop then
          ''
            # Old community installer versions can leave a broken login handler desktop file.
            rm -f "$HOME/.local/share/applications/adskidmgr-opener.desktop"
          ''
        else
          ""
      }

      # Some setups invoke the installer from a deleted/invalid cwd which breaks Wine.
      cd "$HOME"

      exec bash "$INSTALLER_PATH" --proton="$PROTON_VERSION" --default "$@"
    '';
  };
in
lib.mkIf enabled {
  assertions = [
    {
      assertion = protonVersion != "";
      message = "settings.programs.fusion360.protonInstaller.protonVersion must not be empty";
    }
  ];

  home.packages = [ fusion360ProtonSetup ];
}
