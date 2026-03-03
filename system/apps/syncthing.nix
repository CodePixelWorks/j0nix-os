{ config, lib, settings, ... }:
let
  userOverrides = settings.userSettings or { };
  syncthingUsers = lib.filter
    (username:
      let cfg = (((userOverrides.${username} or { }).programs or { }).syncthing or { });
      in cfg.enable or false)
    (builtins.attrNames userOverrides);
  enabled = syncthingUsers != [ ];
  serviceUser = if enabled then builtins.head syncthingUsers else builtins.head (builtins.attrNames userOverrides);
  syncthingCfg = if enabled then (((userOverrides.${serviceUser} or { }).programs or { }).syncthing or { }) else { };
  configDir =
    if (syncthingCfg ? configDir) && syncthingCfg.configDir != null then
      syncthingCfg.configDir
    else if (syncthingCfg ? homeDir) && syncthingCfg.homeDir != null then
      syncthingCfg.homeDir
    else
      "/home/${serviceUser}/.config/syncthing";
  dataDir =
    if (syncthingCfg ? dataDir) && syncthingCfg.dataDir != null then
      syncthingCfg.dataDir
    else
      "/home/${serviceUser}";
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
    user = serviceUser;
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
      assertion = builtins.length syncthingUsers <= 1;
      message = "At most one user may enable userSettings.<name>.programs.syncthing for the shared system Syncthing service.";
    }
    {
      assertion = configDir != "";
      message = "settings.userSettings.<name>.programs.syncthing.configDir must be a non-empty string when set";
    }
    {
      assertion = dataDir != "";
      message = "settings.userSettings.<name>.programs.syncthing.dataDir must be a non-empty string when set";
    }
    {
      assertion = guiAddress != "";
      message = "settings.userSettings.<name>.programs.syncthing.guiAddress must be a non-empty string when set";
    }
    {
      assertion = guiPasswordSecretName == null || guiPasswordSecretName != "";
      message = "settings.userSettings.<name>.programs.syncthing.guiPasswordSecretName must be a non-empty string when set";
    }
    {
      assertion = builtins.isAttrs syncOptions;
      message = "settings.userSettings.<name>.programs.syncthing.options must be an attrset";
    }
    {
      assertion = builtins.isAttrs devices;
      message = "settings.userSettings.<name>.programs.syncthing.devices must be an attrset";
    }
    {
      assertion = builtins.isAttrs folders;
      message = "settings.userSettings.<name>.programs.syncthing.folders must be an attrset";
    }
  ];
}
