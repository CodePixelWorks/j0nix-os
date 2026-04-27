{ config, lib, pkgs, ... }:
let
  cfg = config.programs.autodeskFusion;
  package = cfg.package;
  defaultRoot = "${config.xdg.dataHome}/autodesk-fusion";
  installRoot = if cfg.installDir == null then defaultRoot else cfg.installDir;
  env = {
    FUSION360_ROOT = installRoot;
    FUSION360_GPU_MODE = cfg.gpuMode;
    FUSION360_RUNNER =
      if cfg.installMode == "wine" then "Wine"
      else if cfg.installMode == "wine-fix" then "Wine-fix"
      else cfg.protonVersion;
  } // lib.optionalAttrs (cfg.protonVersion != null) {
    FUSION360_PROTON_DIR = "${cfg.steamDirectory}/compatibilitytools.d/${cfg.protonVersion}";
  };
  envPrefix = lib.concatStringsSep " " (
    lib.mapAttrsToList (name: value: "${name}=${lib.escapeShellArg value}") env
  );
in
{
  options.programs.autodeskFusion = {
    enable = lib.mkEnableOption "Autodesk Fusion on Linux integration";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.autodesk-fusion-linux;
      defaultText = lib.literalExpression "pkgs.autodesk-fusion-linux";
      description = "Package providing Fusion helper commands.";
    };

    addToHomePackages = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the helper package through home.packages.";
    };

    installMode = lib.mkOption {
      type = lib.types.enum [ "wine" "wine-fix" "proton" ];
      default = "wine";
      description = "Runtime mode used for setup, launch, and login callbacks.";
    };

    installDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Mutable per-user Fusion install root. Defaults to XDG data home.";
    };

    gpuMode = lib.mkOption {
      type = lib.types.enum [ "dxvk" "opengl" ];
      default = "dxvk";
      description = "Fusion graphics configuration profile.";
    };

    protonVersion = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Steam compatibility tool name used when installMode is proton.";
    };

    steamDirectory = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/share/Steam";
      description = "Steam installation directory used for Proton mode.";
    };

    autoSetupOnLogin = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Run fusion360-install as a user service after graphical login.";
    };

    desktopEntry.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Create the Fusion desktop entry.";
    };

    urlHandler.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Register the adskidmgr URL handler used by Autodesk login.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = lib.mkIf cfg.addToHomePackages [ package ];

    systemd.user.services.autodesk-fusion-setup = lib.mkIf cfg.autoSetupOnLogin {
      Unit = {
        Description = "Provision Autodesk Fusion Wine prefix";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        Environment = lib.mapAttrsToList (name: value: "${name}=${value}") env;
        ExecStart = "${lib.getExe' package "fusion360-install"}";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    xdg.desktopEntries = lib.mkMerge [
      (lib.mkIf cfg.desktopEntry.enable {
        autodesk-fusion = {
          name = "Autodesk Fusion";
          genericName = "CAD Application";
          comment = "Launch Autodesk Fusion through the managed Linux Wine prefix.";
          type = "Application";
          terminal = false;
          categories = [ "Education" "Engineering" ];
          exec = "${envPrefix} ${lib.getExe' package "fusion360-launch"}";
        };
      })
      (lib.mkIf cfg.urlHandler.enable {
        autodesk-fusion-adskidmgr = {
          name = "Autodesk Fusion Login Callback";
          noDisplay = true;
          type = "Application";
          terminal = false;
          exec = "${envPrefix} ${lib.getExe' package "fusion360-url-handler"} %u";
          mimeType = [ "x-scheme-handler/adskidmgr" ];
        };
      })
      {
        autodesk-fusion-doctor = {
          name = "Autodesk Fusion Doctor";
          noDisplay = true;
          type = "Application";
          terminal = true;
          exec = "${envPrefix} ${lib.getExe' package "fusion360-doctor"}";
        };
      }
    ];

    xdg.mimeApps = lib.mkIf cfg.urlHandler.enable {
      enable = true;
      defaultApplications."x-scheme-handler/adskidmgr" = [ "autodesk-fusion-adskidmgr.desktop" ];
    };

    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
        message = "Autodesk Fusion on Linux is only supported on x86_64-linux.";
      }
      {
        assertion = cfg.installMode != "proton" || cfg.protonVersion != null;
        message = "programs.autodeskFusion.protonVersion must be set when installMode = \"proton\".";
      }
    ];
  };
}
