{ config, lib, settings, ... }:
let
  userOverrides = settings.userSettings or { };
  allUsers = builtins.attrNames userOverrides;
  syncthingUsers = lib.filter
    (username:
      let cfg = (((userOverrides.${username} or { }).programs or { }).syncthing or { });
      in cfg.enable or false)
    allUsers;
  enabled = syncthingUsers != [ ];
  serviceUser = if enabled then builtins.head syncthingUsers else null;
  serviceGroup =
    if serviceUser != null then
      ((config.users.users.${serviceUser} or { }).group or "users")
    else
      null;
  syncthingCfg =
    if serviceUser != null then
      (((userOverrides.${serviceUser} or { }).programs or { }).syncthing or { })
    else
      { };
  configDir =
    if serviceUser == null then
      null
    else if (syncthingCfg ? configDir) && syncthingCfg.configDir != null then
      syncthingCfg.configDir
    else if (syncthingCfg ? homeDir) && syncthingCfg.homeDir != null then
      syncthingCfg.homeDir
    else
      "/home/${serviceUser}/.config/syncthing";
  dataDir =
    if serviceUser == null then
      null
    else if (syncthingCfg ? dataDir) && syncthingCfg.dataDir != null then
      syncthingCfg.dataDir
    else
      "/home/${serviceUser}";
  guiAddress = syncthingCfg.guiAddress or "127.0.0.1:8384";
  guiPasswordSecretName = syncthingCfg.guiPasswordSecretName or null;
  hasGuiPasswordSecret =
    guiPasswordSecretName != null
    && lib.hasAttrByPath [ guiPasswordSecretName ] (config.sops.secrets or { });
  guiPasswordFile =
    if hasGuiPasswordSecret then
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
  warnings = lib.optional
    (guiPasswordSecretName != null && !hasGuiPasswordSecret && (syncthingCfg.guiPasswordFile or null) == null)
    "Syncthing guiPasswordSecretName='${guiPasswordSecretName}' is not available in system sops.secrets. Set services-level secret via settings.secrets.system.<name> or provide settings.userSettings.<name>.programs.syncthing.guiPasswordFile.";

  systemd.services.syncthing.environment.STNODEFAULTFOLDER = "true";

  services.syncthing = {
    enable = true;
    user = serviceUser;
    group = serviceGroup;
    inherit configDir dataDir guiAddress openDefaultPorts overrideDevices overrideFolders;
    inherit guiPasswordFile;
    settings = {
      options = syncOptions;
      inherit devices folders;
    };
  };

  assertions = [
    {
      assertion = allUsers != [ ];
      message = "system/apps/syncthing.nix requires at least one entry in settings.userSettings when syncthing is enabled.";
    }
    {
      assertion = builtins.length syncthingUsers <= 1;
      message = "At most one user may enable userSettings.<name>.programs.syncthing for the shared system Syncthing service.";
    }
    {
      assertion = configDir != "";
      message = "settings.userSettings.<name>.programs.syncthing.configDir must be a non-empty string when set";
    }
    {
      assertion = serviceGroup != null && serviceGroup != "";
      message = "Syncthing service group must resolve to a non-empty group for the selected service user.";
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
