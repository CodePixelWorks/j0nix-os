{ config, lib, settings, ... }:
let
  syncthingCfg = ((settings.programs or { }).syncthing or { });
  enabled = syncthingCfg.enable or true;
  configDir =
    if (syncthingCfg ? configDir) && syncthingCfg.configDir != null then
      syncthingCfg.configDir
    else if (syncthingCfg ? homeDir) && syncthingCfg.homeDir != null then
      syncthingCfg.homeDir
    else
      "/home/${settings.username}/.config/syncthing";
  dataDir =
    if (syncthingCfg ? dataDir) && syncthingCfg.dataDir != null then
      syncthingCfg.dataDir
    else
      "/home/${settings.username}";
  guiAddress = syncthingCfg.guiAddress or "127.0.0.1:8384";
  guiPasswordSecretName = syncthingCfg.guiPasswordSecretName or null;
  guiPasswordFile =
    if guiPasswordSecretName != null then
      config.sops.secrets.${guiPasswordSecretName}.path
    else
      (syncthingCfg.guiPasswordFile or null);
  openDefaultPorts = syncthingCfg.openDefaultPorts or true;
  overrideDevices = syncthingCfg.overrideDevices or false;
  overrideFolders = syncthingCfg.overrideFolders or false;
  syncOptions = syncthingCfg.options or { };
  devices = syncthingCfg.devices or { };
  folders = syncthingCfg.folders or { };
in
lib.mkIf enabled {
  systemd.services.syncthing.environment.STNODEFAULTFOLDER = "true";

  services.syncthing = {
    enable = true;
    user = settings.username;
    group = "users";
    inherit configDir dataDir guiAddress openDefaultPorts overrideDevices overrideFolders;
    inherit guiPasswordFile;
    settings = {
      options = syncOptions;
      inherit devices folders;
    };
  };

  assertions = [
    {
      assertion = configDir != "";
      message = "settings.programs.syncthing.configDir must be a non-empty string when set";
    }
    {
      assertion = dataDir != "";
      message = "settings.programs.syncthing.dataDir must be a non-empty string when set";
    }
    {
      assertion = guiAddress != "";
      message = "settings.programs.syncthing.guiAddress must be a non-empty string when set";
    }
    {
      assertion = guiPasswordSecretName == null || guiPasswordSecretName != "";
      message = "settings.programs.syncthing.guiPasswordSecretName must be a non-empty string when set";
    }
    {
      assertion = builtins.isAttrs syncOptions;
      message = "settings.programs.syncthing.options must be an attrset";
    }
    {
      assertion = builtins.isAttrs devices;
      message = "settings.programs.syncthing.devices must be an attrset";
    }
    {
      assertion = builtins.isAttrs folders;
      message = "settings.programs.syncthing.folders must be an attrset";
    }
  ];
}
