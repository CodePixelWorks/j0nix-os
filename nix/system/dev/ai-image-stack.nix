{
  config,
  lib,
  pkgs,
  settings,
  utils,
  ...
}:
let
  dev = settings.dev or { };
  ai = dev.ai or { };
  cfg = ai.image or { };
  enabled = cfg.enable or false;
  apps = cfg.apps or { };

  nvidiaEnabled = ((config.j0nix.desktop.drivers or { }).nvidia or { }).enable or false;
  useNvidia = cfg.useNvidia or nvidiaEnabled;
  uid = cfg.uid or 1000;
  gid = cfg.gid or 100;
  baseDir = cfg.baseDir or "/var/lib/j0nix-ai";
  host = cfg.host or "127.0.0.1";
  autoStartDefault = cfg.autoStart or false;

  storageCfg = settings.storage or { };
  systemMounts = storageCfg.systemMounts or [ ];
  isPathUnderMount =
    mountPoint: path:
    let
      mp = lib.removeSuffix "/" mountPoint;
      p = lib.removeSuffix "/" path;
    in
    p == mp || lib.hasPrefix "${mp}/" p;
  parentMount = lib.findFirst (
    m: (m.enable or true) && isPathUnderMount m.mountPoint baseDir
  ) null systemMounts;
  parentMountUnit =
    if parentMount != null && (parentMount.automount or false) then
      "${utils.escapeSystemdPath (lib.removeSuffix "/" parentMount.mountPoint)}.mount"
    else
      null;

  modelsDir = cfg.modelsDir or "${baseDir}/models";
  outputsDir = cfg.outputsDir or "${baseDir}/outputs";
  inputsDir = cfg.inputsDir or "${baseDir}/input";
  workflowsDir = cfg.workflowsDir or "${baseDir}/workflows";
  cacheDir = cfg.cacheDir or "${baseDir}/cache";
  stateDir = cfg.stateDir or "${baseDir}/state";
  appsDir = cfg.appsDir or "${baseDir}/apps";

  modelSubdirs =
    cfg.modelSubdirs or [
      "checkpoints"
      "clip"
      "clip_vision"
      "controlnet"
      "diffusion_models"
      "embeddings"
      "loras"
      "unet"
      "upscale_models"
      "vae"
    ];

  commonEnv = {
    HF_HOME = "/data/cache/huggingface";
    HUGGINGFACE_HUB_CACHE = "/data/cache/huggingface/hub";
    TRANSFORMERS_CACHE = "/data/cache/huggingface/transformers";
    XDG_CACHE_HOME = "/data/cache/xdg";
    PUID = toString uid;
    PGID = toString gid;
  }
  // (cfg.environment or { });

  nvidiaExtraOptions = lib.optionals useNvidia [
    "--device=nvidia.com/gpu=all"
  ];

  mkPort = app: "${host}:${toString app.port}:${toString app.containerPort}";

  appDefaults = {
    comfyui = {
      enable = apps.comfyui.enable or true;
      autoStart = apps.comfyui.autoStart or autoStartDefault;
      image = apps.comfyui.image or "ghcr.io/ai-dock/comfyui:latest-cuda";
      port = apps.comfyui.port or 8188;
      containerPort = apps.comfyui.containerPort or 8188;
      environment = {
        COMFYUI_ARGS = apps.comfyui.comfyArgs or "--listen 0.0.0.0";
        COMFYUI_PORT_HOST = toString (apps.comfyui.containerPort or 8188);
        WEB_ENABLE_AUTH = "false";
      }
      // (apps.comfyui.environment or { });
      volumes = [
        "${stateDir}/comfyui:/workspace"
        "${modelsDir}:/workspace/ComfyUI/models"
        "${outputsDir}/comfyui:/workspace/ComfyUI/output"
        "${inputsDir}:/workspace/ComfyUI/input"
        "${workflowsDir}/comfyui:/workspace/ComfyUI/user/default/workflows"
        "${cacheDir}:/data/cache"
      ]
      ++ (apps.comfyui.volumes or [ ]);
      extraOptions = nvidiaExtraOptions ++ (apps.comfyui.extraOptions or [ ]);
    };

    invoke = {
      enable = apps.invoke.enable or true;
      autoStart = apps.invoke.autoStart or autoStartDefault;
      image = apps.invoke.image or "ghcr.io/invoke-ai/invokeai:latest";
      port = apps.invoke.port or 9090;
      containerPort = apps.invoke.containerPort or 9090;
      environment = {
        INVOKEAI_ROOT = "/invokeai";
      }
      // (apps.invoke.environment or { });
      volumes = [
        "${stateDir}/invokeai:/invokeai"
        "${modelsDir}:/invokeai/models"
        "${outputsDir}/invoke:/invokeai/outputs"
        "${inputsDir}:/invokeai/input"
        "${cacheDir}:/data/cache"
      ]
      ++ (apps.invoke.volumes or [ ]);
      extraOptions = nvidiaExtraOptions ++ (apps.invoke.extraOptions or [ ]);
    };
  };

  enabledOciApps = lib.filterAttrs (_: app: app.enable) appDefaults;

  swarmCfg = apps.swarmui or { };
  swarm = {
    enable = swarmCfg.enable or true;
    autoStart = swarmCfg.autoStart or autoStartDefault;
    repo = swarmCfg.repo or "https://github.com/mcmonkeyprojects/SwarmUI.git";
    ref = swarmCfg.ref or "master";
    port = swarmCfg.port or 7801;
    containerPort = swarmCfg.containerPort or 7801;
    sourceDir = swarmCfg.sourceDir or "${appsDir}/swarmui/source";
    image = swarmCfg.image or "swarmui-j0nix";
    extraCompose = swarmCfg.extraCompose or { };
  };

  swarmCompose = pkgs.writeText "swarmui-compose.yaml" (
    lib.generators.toYAML { } (
      {
        services.swarmui = {
          image = swarm.image;
          build = {
            context = swarm.sourceDir;
            dockerfile = "launchtools/StandardDockerfile.docker";
            args.UID = toString uid;
          };
          container_name = "ai-swarmui";
          user = "${toString uid}:${toString gid}";
          cap_drop = [ "ALL" ];
          ports = [
            "${host}:${toString swarm.port}:${toString swarm.containerPort}"
          ];
          volumes = [
            "${stateDir}/swarmui/data:/SwarmUI/Data"
            "${stateDir}/swarmui/backend:/SwarmUI/dlbackend"
            "${stateDir}/swarmui/dlnodes:/SwarmUI/src/BuiltinExtensions/ComfyUIBackend/DLNodes"
            "${stateDir}/swarmui/extensions:/SwarmUI/src/Extensions"
            "${modelsDir}:/SwarmUI/Models"
            "${outputsDir}/swarmui:/SwarmUI/Output"
            "${workflowsDir}/swarmui:/SwarmUI/src/BuiltinExtensions/ComfyUIBackend/CustomWorkflows"
          ];
          environment = commonEnv;
        }
        // lib.optionalAttrs useNvidia {
          deploy.resources.reservations.devices = [
            {
              driver = "nvidia";
              count = "all";
              capabilities = [ "gpu" ];
            }
          ];
        };
      }
      // swarm.extraCompose
    )
  );

  swarmRun = pkgs.writeShellApplication {
    name = "ai-swarmui-run";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.docker
    ];
    text = ''
      set -eu

      source_dir=${lib.escapeShellArg swarm.sourceDir}
      mkdir -p "$(dirname "$source_dir")"

      if [ ! -d "$source_dir/.git" ]; then
        git clone --branch ${lib.escapeShellArg swarm.ref} --depth 1 ${lib.escapeShellArg swarm.repo} "$source_dir"
      else
        git -C "$source_dir" fetch --depth 1 origin ${lib.escapeShellArg swarm.ref}
        git -C "$source_dir" reset --hard FETCH_HEAD
      fi

      exec docker compose -f ${swarmCompose} up --build
    '';
  };

  swarmStop = pkgs.writeShellApplication {
    name = "ai-swarmui-compose-down";
    runtimeInputs = [
      pkgs.docker
    ];
    text = ''
      exec docker compose -f ${swarmCompose} down
    '';
  };

  mkLauncher =
    name: url: service:
    pkgs.writeShellApplication {
      name = "ai-${name}";
      runtimeInputs = [
        pkgs.systemd
        pkgs.xdg-utils
      ];
      text = ''
        action="''${1:-open}"
        case "$action" in
          start)
            exec systemctl start ${service}
            ;;
          stop)
            exec systemctl stop ${service}
            ;;
          restart)
            exec systemctl restart ${service}
            ;;
          status)
            exec systemctl status ${service} --no-pager
            ;;
          open)
            systemctl start ${service}
            exec xdg-open ${lib.escapeShellArg url}
            ;;
          *)
            echo "Usage: ai-${name} [open|start|stop|restart|status]" >&2
            exit 2
            ;;
        esac
      '';
    };

  stackLauncher = pkgs.writeShellApplication {
    name = "ai-image-stack";
    runtimeInputs = [
      pkgs.systemd
    ];
    text = ''
      action="''${1:-status}"
      case "$action" in
        start|stop|restart|status)
          systemctl "$action" ${
            lib.concatStringsSep " " (
              (map (name: "docker-ai-${name}.service") (builtins.attrNames enabledOciApps))
              ++ lib.optional swarm.enable "ai-swarmui.service"
            )
          }
          ;;
        *)
          echo "Usage: ai-image-stack [start|stop|restart|status]" >&2
          exit 2
          ;;
      esac
    '';
  };

  prepareDirs = [
    baseDir
    modelsDir
    outputsDir
    "${outputsDir}/comfyui"
    "${outputsDir}/invoke"
    "${outputsDir}/swarmui"
    inputsDir
    workflowsDir
    "${workflowsDir}/comfyui"
    "${workflowsDir}/swarmui"
    cacheDir
    "${cacheDir}/huggingface"
    "${cacheDir}/huggingface/hub"
    "${cacheDir}/huggingface/transformers"
    "${cacheDir}/xdg"
    stateDir
    "${stateDir}/comfyui"
    "${stateDir}/invokeai"
    "${stateDir}/swarmui/data"
    "${stateDir}/swarmui/backend"
    "${stateDir}/swarmui/dlnodes"
    "${stateDir}/swarmui/extensions"
    appsDir
    (builtins.dirOf swarm.sourceDir)
  ]
  ++ map (subdir: "${modelsDir}/${subdir}") modelSubdirs;
in
lib.mkIf enabled {
  virtualisation = {
    docker.enable = true;
    oci-containers = {
      backend = lib.mkDefault "docker";
      containers = lib.mapAttrs' (
        name: app:
        lib.nameValuePair "ai-${name}" {
          inherit (app)
            image
            autoStart
            volumes
            extraOptions
            ;
          ports = [ (mkPort app) ];
          environment = commonEnv // app.environment;
        }
      ) enabledOciApps;
    };
  };

  hardware.nvidia-container-toolkit.enable = lib.mkIf useNvidia true;

  systemd.services = {
    ai-image-stack-prepare = {
      description = "Prepare shared AI image stack directories";
      after = lib.optional (parentMountUnit != null) parentMountUnit;
      requires = lib.optional (parentMountUnit != null) parentMountUnit;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu

        for dir in ${lib.concatStringsSep " " (map lib.escapeShellArg prepareDirs)}; do
          ${lib.getExe' pkgs.coreutils "install"} -d -m 2775 -o root -g users "$dir"
        done
      '';
    };
  }
  // (lib.mapAttrs' (
    name: _:
    lib.nameValuePair "docker-ai-${name}" {
      after = [
        "ai-image-stack-prepare.service"
      ]
      ++ lib.optional (parentMountUnit != null) parentMountUnit;
      requires = [
        "ai-image-stack-prepare.service"
      ]
      ++ lib.optional (parentMountUnit != null) parentMountUnit;
    }
  ) enabledOciApps)
  // lib.optionalAttrs swarm.enable {
    ai-swarmui = {
      description = "SwarmUI AI image generation web UI";
      wantedBy = lib.optionals swarm.autoStart [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "docker.service"
        "network-online.target"
        "ai-image-stack-prepare.service"
      ]
      ++ lib.optional (parentMountUnit != null) parentMountUnit;
      requires = [
        "docker.service"
        "ai-image-stack-prepare.service"
      ]
      ++ lib.optional (parentMountUnit != null) parentMountUnit;
      serviceConfig = {
        Type = "simple";
        ExecStart = lib.getExe swarmRun;
        ExecStop = lib.getExe swarmStop;
        WorkingDirectory = appsDir;
        Restart = "on-failure";
        RestartSec = 10;
        TimeoutStartSec = "30min";
      };
    };
  };

  j0nix.software.systemPackages = [
    stackLauncher
  ]
  ++ lib.optional appDefaults.comfyui.enable (
    mkLauncher "comfyui" "http://${host}:${toString appDefaults.comfyui.port}"
      "docker-ai-comfyui.service"
  )
  ++ lib.optional appDefaults.invoke.enable (
    mkLauncher "invoke" "http://${host}:${toString appDefaults.invoke.port}" "docker-ai-invoke.service"
  )
  ++ lib.optional swarm.enable (
    mkLauncher "swarmui" "http://${host}:${toString swarm.port}" "ai-swarmui.service"
  );

  assertions = [
    {
      assertion = builtins.isString baseDir && lib.hasPrefix "/" baseDir;
      message = "settings.dev.ai.image.baseDir must be an absolute path";
    }
    {
      assertion = builtins.isInt uid && uid > 0;
      message = "settings.dev.ai.image.uid must be a positive integer";
    }
    {
      assertion = builtins.isInt gid && gid > 0;
      message = "settings.dev.ai.image.gid must be a positive integer";
    }
    {
      assertion = builtins.isBool useNvidia;
      message = "settings.dev.ai.image.useNvidia must be a boolean";
    }
    {
      assertion = builtins.isList modelSubdirs && lib.all builtins.isString modelSubdirs;
      message = "settings.dev.ai.image.modelSubdirs must be a list of strings";
    }
  ];
}
