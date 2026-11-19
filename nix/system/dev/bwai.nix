# bwai.nix — bubblewrap-ai (bwai) sandbox module for j0nix-os
# (ported from nixos-server-base modules/stacks/operations/bubblewrap-ai.nix,
#  option namespace j0nix.desktop.dev.bwai).
#
# Installs the bwai CLI system-wide so AI coding agents can be run
# inside a bubblewrap sandbox:
#   - host filesystem read-only (except explicitly mounted work dirs)
#   - only whitelisted dotfiles / home dirs and work dirs writable
#   - only allowlisted env vars exposed
#
# This is the lightweight companion to terok (Podman-based):
# no daemon, no images, millisecond startup.
#
# Unlike upstream's manual ~/.bwai.json, this module renders each user's
# bwai policy DECLARATIVELY from Nix and writes it under /etc/bwai/ (NOT
# in $HOME), so no config clutter pollutes the home dir. Two wrappers
# auto-select the right config for the invoking user:
#   bwai        -> /etc/bwai/<user>.json      (interactive)
#   bwai-agent  -> /etc/bwai/<user>.agent.json (Hermes/agent, stricter)
#
# The default policy:
#   - work dirs (workDirs, e.g. projects) read-write
#   - secret/hidden dotfiles (homeBlock: .ssh/.gnupg/.aws/.kube/...) never
#     exposed
#   - minimal env_allow (no secrets leak, LLM keys opt-in via envAllow)
#   - /nix + system runtime dirs bound read-only so tools/packages work
#
# Auth sockets:
#   When `propagateAuthSockets = true`, the user's /run/user (home of the
#   ssh-agent and gpg-agent sockets) is bound read-only and SSH_AUTH_SOCK /
#   GPG_AGENT_INFO are passed through env_allow. The CLI's --clearenv then
#   sets the *host* socket path, which resolves inside the sandbox via the
#   ro-bind. The agent can perform SIGNING operations through the already
#   running agent, but the private keys (.ssh/.gnupg, home_block) are never
#   exposed — the socket carries no key material itself.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types concatStringsSep optionalString;
  inherit (lib.generators) toJSON;

  cfg = config.j0nix.desktop.dev.bwai;

  # Default secrets/hidden dotfiles that must never reach the agent.
  defaultHomeBlock = [
    ".gnupg"
    ".ssh"
    ".pki"
    ".aws"
    ".kube"
    ".azure"
    ".bashrc"
    ".bashrc.d"
    ".password-store"
    ".bash_history*"
    ".config/Bitwarden"
    ".cache/nvidia"
  ];

  # Default dotfiles every agent needs (identity, git config, caches).
  defaultHomeAllow = [
    ".claude"
    ".claude.json"
    ".gemini"
    ".config/goose"
    ".config/gcloud"
    ".local/state"
    ".local/share/goose"
    ".cache"
    ".cargo"
    ".gitconfig"
  ];

  # Default env vars (locale + editor, no secrets).
  defaultEnvAllow = [
    "TERM"
    "COLORTERM"
    "LANG"
    "LC_ALL"
    "LC_MESSAGES"
    "LC_CTYPE"
    "HOME"
    "USER"
    "LOGNAME"
    "PATH"
    "EDITOR"
  ];

  # Base extra bwrap args (read-only system exposure so tools work).
  baseBwrapArgs = [
    "--ro-bind /nix /nix"
    "--ro-bind /run/current-system /run/current-system"
    "--ro-bind /run/wrappers /run/wrappers"
    "--proc /proc"
    "--dev /dev"
  ];

  # bwai needs bwrap on PATH at runtime. Wrap the CLI so the sandbox works
  # no matter which shell profile the user has.
  bwaiReal = pkgs.symlinkJoin {
    name = "bwai-real";
    paths = [ cfg.package ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/bwai \
        --prefix PATH : ${lib.makeBinPath [ pkgs.bubblewrap ]}
    '';
  };

  # Two thin wrappers that select the per-user config automatically.
  # User-passed --config (appended) wins over ours, so override stays possible.
  # They prepend the gpg shim's store bin dir to PATH so the sandbox resolves
  # `gpg` to the shim (which relays to the broker for broker users, and
  # degrades to the real gpg otherwise).
  bwaiInteractive = pkgs.writeShellScriptBin "bwai" ''
    export PATH=${gpgShimBin}/bin:"$PATH"
    export GPG_BROKER_SOCK=/run/gpg-broker/$(id -u -n).sock
    # Source per-user explicit env (setEnv option) so bwai forwards it.
    _bwai_env="/etc/bwai/$(id -u -n).env"
    [ -f "$_bwai_env" ] && . "$_bwai_env"
    # Source per-user secret env (setEnvFile option — e.g. SOPS env).
    # Values live only in this process env; bwai --clearenv re-injects
    # exactly the names whitelisted in env_allow.
    _bwai_secret_env="/etc/bwai/$(id -u -n).secret.env"
    [ -f "$_bwai_secret_env" ] && . "$_bwai_secret_env"
    exec ${bwaiReal}/bin/bwai --config /etc/bwai/$(id -u -n).json "$@"
  '';
  bwaiAgent = pkgs.writeShellScriptBin "bwai-agent" ''
    export PATH=${gpgShimBin}/bin:"$PATH"
    export GPG_BROKER_SOCK=/run/gpg-broker/$(id -u -n).sock
    # Source per-user explicit env (setEnv option).
    _bwai_env="/etc/bwai/$(id -u -n).env"
    [ -f "$_bwai_env" ] && . "$_bwai_env"
    # Source per-user secret env (setEnvFile option — e.g. SOPS env).
    _bwai_secret_env="/etc/bwai/$(id -u -n).secret.env"
    [ -f "$_bwai_secret_env" ] && . "$_bwai_secret_env"
    exec ${bwaiReal}/bin/bwai --config /etc/bwai/$(id -u -n).agent.json "$@"
  '';

  # gpg sign-broker + sandbox shim.
  #
  # The broker runs as the target user with the real GNUPGHOME and performs
  # allowed gpg operations (signing) on their behalf over a unix socket; the
  # real gpg-agent holds the (unlocked) secret keys in memory. The sandbox's
  # `gpg` is replaced by a shim that relays signing requests to the broker, so
  # the sandbox can sign (e.g. `git commit -S`) WITHOUT ever seeing
  # private-keys-v1.d/ (the actual key material). Secret-revealing operations
  # (--export-secret-keys, --import, ...) are denied by the broker.
  gpgBrokerBin = pkgs.writeScriptBin "gpg-broker" ''
    #!${pkgs.python3}/bin/python3
    ${builtins.readFile ./gpg-broker.py}
  '';
  gpgShimBin = pkgs.writeScriptBin "gpg" ''
    #!${pkgs.python3}/bin/python3
    ${builtins.readFile ./gpg-shim.py}
  '';
in
{
  options.j0nix.desktop.dev.bwai = {
    enable = mkEnableOption "the bubblewrap-ai (bwai) sandbox CLI for AI coding agents";

    package = mkOption {
      type = types.package;
      default = pkgs.bubblewrap-ai;
      defaultText = "pkgs.bubblewrap-ai";
      description = "The bubblewrap-ai package to install.";
    };

    # Config root (outside $HOME, so no home clutter). Per-user JSON files
    # land at ${configRoot}/<user>.json (and .agent.json).
    configRoot = mkOption {
      type = types.str;
      default = "/etc/bwai";
      description = "Directory holding per-user bwai configs (outside $HOME).";
    };

    users = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          homeAllow = mkOption {
            type = types.listOf types.str;
            default = defaultHomeAllow;
            description = "Dotfiles/dirs under $HOME the agent may read AND write (rel. to $HOME).";
          };
          homeBlock = mkOption {
            type = types.listOf types.str;
            default = defaultHomeBlock;
            description = "Dotfiles/dirs under $HOME never exposed. Precedence over homeAllow at same nesting level.";
          };
          envAllow = mkOption {
            type = types.listOf types.str;
            default = defaultEnvAllow;
            description = "Host env vars passed into the sandbox (LLM keys opt-in here).";
          };
          # Binds of paths OUTSIDE $HOME the agent needs (e.g. the Hermes
          # service state dir holding .env + config.yaml + its state.db).
          # Each entry is bound READ-WRITE at the same absolute path — Hermes
          # must write state.db/logs/locks in its HERMES_HOME. Files inside
          # belong to the same user the agent runs as.
          extraBinds = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = ''
              Host paths (absolute) to bind read-write into the sandbox at
              their same location. Use for state dirs outside $HOME the
              agent must write to (e.g. /var/lib/hermes-jonas for Hermes
              agents running with HERMES_HOME there).
            '';
          };

          extraRoBinds = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = ''
              Host paths (absolute) to bind read-only into the sandbox at
              their same location. Use for broker socket directories
              (e.g. /run/tnnl-broker): connecting to a unix socket works
              through a read-only bind — connect(2) does not modify the
              filesystem — while the broker-side SO_PEERCRED gate stays
              the authority on who may talk. Secrets behind the broker
              never become readable this way.
            '';
          };
          # Env vars to SET in the sandbox regardless of the host env (bwai
          # only forwards host-set vars via env_allow; vars the invoking
          # process doesn't have — like HERMES_HOME for a shell-invoked
          # agent — need explicit values). Format: "NAME=value".
          setEnv = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = ''
              Environment variables to set explicitly in the sandbox
              ("NAME=value"). Needed for vars bwai's env_allow cannot
              forward because they are not set in the invoking host env
              (e.g. HERMES_HOME=/var/lib/hermes-jonas).
            '';
          };

          # Secret-bearing env sourced from a runtime file (e.g. a SOPS
          # env secret) instead of baking values into the world-readable
          # /etc/bwai config. Only the var NAMES from this file are added
          # to env_allow; the VALUES are sourced at invocation time by
          # the wrapper (which runs as the user, before --clearenv).
          setEnvFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = ''
              Path to an env file (e.g. a SOPS secret of type `env`)
              whose variables are injected into the sandbox. The wrapper
              sources this file before exec'ing bwai, so values never
              touch the Nix store or the 0644 /etc/bwai policy files.
              Variable NAMES are appended to env_allow automatically
              (plus setEnv names). The file must be readable by the
              user running the wrapper.

              Use this for secrets (LLM keys, account-scoped API
              tokens); use `setEnv` for non-secret values.
            '';
          };
          bwrapExtraArgs = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Extra bwrap args (work dirs as --ro-bind, --unshare-net, etc.).";
          };
          workDirs = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Non-hidden work dirs under $HOME (e.g. `projects`) exposed read-write, via home_allow.";
          };
          command = mkOption {
            type = types.listOf types.str;
            default = [ "bash" ];
            description = "Command to run inside the sandbox.";
          };
          # Propagate the user's auth sockets (ssh-agent + gpg-agent) into
          # the sandbox so the agent can perform SIGNING operations via the
          # existing agent, while the private-key dirs (.ssh/.gnupg) stay in
          # home_block. The socket carries no key material itself.
          propagateAuthSockets = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Bind the user's auth sockets read-only into the sandbox and
              pass SSH_AUTH_SOCK through env_allow. Lets the agent sign via
              the already-running ssh-agent (at /run/user-ssh-agents/<user>.sock)
              and gpg-agent (sockets bound individually) without ever
              exposing the private keys (.ssh/.gnupg stay blocked).
            '';
          };
          # gpg-agent socket FILES under ~/.gnupg to bind read-only when
          # propagateAuthSockets is on. Only these sockets are exposed;
          # private-keys-v1.d/ and the rest of .gnupg stay hidden.
          gpgAgentSockets = mkOption {
            type = types.listOf types.str;
            default = [ "S.gpg-agent" "S.gpg-agent.ssh" "S.gpg-agent.extra" ];
            description = "gpg-agent socket filenames under ~/.gnupg to bind read-only into the sandbox.";
          };
          # Agent variant: also write <configRoot>/<user>.agent.json, with
          # SSH_AUTH_SOCK/GPG_AGENT_INFO stripped unless propagateAuthSockets.
          agentVariant = mkOption {
            type = types.bool;
            default = false;
            description = "Also write .agent.json (for Hermes/agent use via bwai-agent).";
          };
          # Enable the gpg sign-broker for this user: a gpg shim inside the
          # sandbox relays signing requests to a host-side broker (running
          # with the real GNUPGHOME), so `git commit -S` etc. work WITHOUT
          # exposing private-keys-v1.d/. Secret-revealing ops are denied.
          gpgBroker = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Run the gpg sign-broker for this user and shadow gpg inside the
              sandbox with a shim that signs via the broker. Enables gpg
              signing (e.g. git commit -S) without ever exposing the secret
              key material (private-keys-v1.d stays blocked). Signing-only;
              secret-revealing operations are refused by the broker.
            '';
          };
        };
      });
      default = { };
      description = "Per-user bwai sandbox policies. Each entry yields a config under serverStacks.apps.bubblewrapAi.configRoot.";
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      environment.systemPackages = [ bwaiInteractive bwaiAgent ];

    # gpg sign-broker services (one per user with gpgBroker enabled) + the
    # per-user config materialiser — all merged under one systemd.services.
    systemd.services =
      # gpg sign-broker: runs as the user with the real GNUPGHOME; exposes
      # /run/gpg-broker/<user>.sock so the sandbox shim can sign.
      lib.optionalAttrs (lib.any (u: u.gpgBroker) (lib.attrValues cfg.users)) (
        lib.mapAttrs' (userName: userCfg:
          lib.nameValuePair "bwai-gpg-broker-${userName}" (lib.optionalAttrs userCfg.gpgBroker {
            description = "gpg sign-broker for ${userName} (bwai sandbox)";
            wantedBy = [ "multi-user.target" ];
            after = [ "network.target" ];
            serviceConfig = {
              Type = "simple";
              User = userName;
              Group = "users";
              Restart = "on-failure";
              RestartSec = "2";
              RuntimeDirectory = "gpg-broker";
              RuntimeDirectoryMode = "0750";
              ExecStart = "${gpgBrokerBin}/bin/gpg-broker";
              Environment = [
                "BROKER_USER=${userName}"
                "BROKER_GNUPGHOME=${config.users.users.${userName}.home or "/home/${userName}"}/.gnupg"
                "BROKER_HOME=${config.users.users.${userName}.home or "/home/${userName}"}"
                # Resolve to the real gpg binary — the default
                # /run/current-system/sw/bin/gpg doesn't exist on this system.
                "BROKER_GPG=${pkgs.gnupg}/bin/gpg"
              ];
            };
            path = [ pkgs.gnupg pkgs.python3 ];
          }))
        cfg.users
      )
      // lib.optionalAttrs (cfg.users != { }) {
        # Install per-user configs under ${cfg.configRoot} (root-owned, 0644 —
        # the policy is not secret: anyone may read what's exposed/blocked).
        bwai-user-configs = {
          description = "Materialise per-user bwai sandbox configs";
          wantedBy = [ "multi-user.target" ];
          after = [ "systemd-tmpfiles-setup.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [ pkgs.coreutils pkgs.jq ];
          script =
            let
              render = userName: userCfg: variant:
                let
                  home = config.users.users.${userName}.home or "/home/${userName}";
                  ha = userCfg.homeAllow ++ userCfg.workDirs;
                  hb = userCfg.homeBlock;
                  # Auth socket propagation. SSH: the framework bot-run
                  # ssh-agent lives at /run/user-ssh-agents/<user>.sock (a
                  # system-owned path — clean to bind; contains no keys). GPG:
                  # the agent sockets live INSIDE ~/.gnupg (blocked), so bind
                  # only the individual socket FILES read-only over the
                  # home_block tmpfs (bwrap applies args in order) — the agent
                  # can reach the running gpg-agent, but private-keys-v1.d/ and
                  # everything else in .gnupg stays hidden.
                  sshSock = "/run/user-ssh-agents/${userName}.sock";
                  # gpg shim: place the shim at a path that shadows the real gpg.
                  # The sandbox binds /etc read-only (gpg lives there via the user
                  # profile), so we bind the shim binary read-only OVER the real
                  # gpg at its resolved location, and pass GPG_BROKER_SOCK.
                  gpgShimArg = lib.optionals userCfg.gpgBroker [
                    # Replace the REAL gpg binary at its store path with the
                    # shim via ro-bind. Not `-ro-bind-try` (the file must
                    # exist — it does, since this is the same pkgs.gnupg the
                    # broker uses, which in the deployed system IS the user's
                    # gpg, verified via BROKER_GPG). Survives any --command
                    # override because `which gpg` resolves the user-profile
                    # symlink into this store path.
                    "--ro-bind ${gpgShimBin}/bin/gpg ${pkgs.gnupg}/bin/gpg"
                    "--ro-bind-try /run/gpg-broker /run/gpg-broker"
                  ];
                  authArgs =
                    if userCfg.propagateAuthSockets
                    then
                      [ "--ro-bind-try /run/user-ssh-agents /run/user-ssh-agents" ]
                      ++ (map
                        (s: "--ro-bind-try ${home}/.gnupg/${s} ${home}/.gnupg/${s}")
                        userCfg.gpgAgentSockets)
                      ++ gpgShimArg
                    else gpgShimArg;
                  # Read-write binds of absolute host paths (agent state dirs
                  # outside $HOME, e.g. the Hermes service state dir).
                  extraBindArgs = map
                    (p: "--bind ${p} ${p}")
                    userCfg.extraBinds;
                  # Read-only binds (broker socket dirs etc.) — see the
                  # extraRoBinds option docs for the security rationale.
                  extraRoBindArgs = map
                    (p: "--ro-bind-try ${p} ${p}")
                    userCfg.extraRoBinds;
                  # Explicit env vars: rendered to <configRoot>/<user>.env and
                  # sourced by the bwai wrapper (NOT via bwrap --setenv, which
                  # cannot take a value as a separate argv element through
                  # bwai's string-array extra_args). The wrapper exports them
                  # into the invoking host env so bwai's env_allow forwards
                  # them — that also survives --command overrides. Var NAMES
                  # are added to env_allow automatically.
                  setEnvNames = map (kv: lib.head (lib.splitString "=" kv)) userCfg.setEnv;
                  authEnv =
                    lib.optionals (userCfg.propagateAuthSockets)
                      # SSH_AUTH_SOCK is set to the exact host socket path so the
                      # CLI's --clearenv bookkeeping matches the bound path. GPG
                      # resolves its socket via GNUPGHOME (kept as-is).
                      [ "SSH_AUTH_SOCK" ]
                    ++ lib.optionals userCfg.gpgBroker
                      [ "GPG_BROKER_SOCK" ]
                    # setEnv names are exported by the wrapper before bwai
                    # starts, so env_allow must list them for forwarding.
                    ++ setEnvNames;
                  eAllow =
                    let
                      base = lib.unique (userCfg.envAllow ++ authEnv);
                    in
                    # Agent variant without socket propagation: strip the socket
                    # env vars so no path to a nonexposed agent leaks.
                    if variant == "agent" && !userCfg.propagateAuthSockets
                    then lib.filter (x: x != "SSH_AUTH_SOCK") base
                    else base;
                    json = toJSON { } {
                      bwrap_path = "bwrap";
                      bwrap_extra_args = lib.unique (baseBwrapArgs ++ authArgs ++ extraBindArgs ++ extraRoBindArgs ++ userCfg.bwrapExtraArgs);
                      # gpg is replaced at its store path by the shim via
                      # gpgShimArg ro-bind, so `command` needs no PATH hack.
                      command = userCfg.command;
                      home_allow = ha;
                    home_block = hb;
                    env_allow = eAllow;
                  };
                  fname = if variant == "agent" then "${userName}.agent.json" else "${userName}.json";
                  envFile = optionalString (variant == "interactive" && userCfg.setEnv != [ ]) ''
                    cat > "${cfg.configRoot}/${userName}.env" <<'EOF'
                    ${concatStringsSep "\n" userCfg.setEnv}
                    EOF
                    chmod 0644 "${cfg.configRoot}/${userName}.env"
                  '';
                  # setEnvFile: copy the secret env file into configRoot
                  # as <user>.secret.env (0400, owned by the user — the
                  # wrapper sources it at invocation time). Only the var
                  # NAMES are additionally written into the 0644 policy
                  # JSON so bwai's --clearenv forwards them; the values
                  # stay in the user-owned 0400 file. The materialiser
                  # runs as root on the host, after sops-install-secrets.
                  #
                  # Guards: skip when the secret file does not exist YET
                  # (first-boot ordering — the path unit below re-runs the
                  # materialiser when it appears) or is empty.
                  secretEnv =
                    let
                      sf = toString userCfg.setEnvFile;
                    in
                    optionalString (userCfg.setEnvFile != null) ''
                      if [ -s "${sf}" ]; then
                        install -m 0400 -o ${userName} -g ${config.users.users.${userName}.group or "users"} \
                          "${sf}" "${cfg.configRoot}/${userName}.secret.env"
                        names="$(sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' \
                          "${sf}" | sort -u)"
                        jq --argjson names "$(printf '%s\n' "$names" | jq -R . | jq -s .)" \
                          '.env_allow = ((.env_allow + $names) | unique)' \
                          "${cfg.configRoot}/${fname}" \
                          > "${cfg.configRoot}/${fname}.tmp" \
                          && mv "${cfg.configRoot}/${fname}.tmp" "${cfg.configRoot}/${fname}"
                      fi
                    '';
                in
                ''
                  mkdir -p "${cfg.configRoot}"
                  # Remove any legacy config that a previous (home-dir) deploy
                  # left in $HOME — configs now live under ${cfg.configRoot}.
                  rm -f "${home}/.bwai.json" "${home}/.bwai-agent.json" 2>/dev/null || true
                  cat > "${cfg.configRoot}/${fname}" <<'EOF'
                  ${json}
                  EOF
                  chmod 0644 "${cfg.configRoot}/${fname}"
                  ${envFile}
                  ${secretEnv}
                '';
            in
            concatStringsSep "\n" (lib.mapAttrsToList
              (userName: userCfg:
                render userName userCfg "interactive"
                + optionalString userCfg.agentVariant (render userName userCfg "agent"))
              cfg.users);
        };
      };
    })
    # Re-materialise when a setEnvFile secret changes (SOPS rotation):
    # each setEnvFile user gets a path unit watching their file. The
    # materialiser is idempotent — a re-run re-renders every config
    # and re-merges the secret env names into env_allow.
    #
    # NOTE: this is a SIBLING of systemd.services in the config
    # attrset, NOT a `// optionalAttrs` on the services value — that
    # form silently nested systemd.paths INTO systemd.services
    # (services."systemd".paths, eval error "The option
    # `systemd.services.systemd.paths' does not exist", surfaced
    # 2026-10-19 when the first host actually used setEnvFile).
    (lib.mkIf (lib.any (u: u.setEnvFile != null) (lib.attrValues cfg.users)) {
      systemd.paths = lib.mapAttrs'
        (userName: userCfg: lib.nameValuePair
          "bwai-user-configs-${userName}-env"
          {
            description = "Watch ${userName}'s bwai setEnvFile for changes";
            wantedBy = [ "multi-user.target" ];
            pathConfig.PathChanged = toString userCfg.setEnvFile;
            unitConfig.Requires = "bwai-user-configs.service";
          })
        (lib.filterAttrs (_: u: u.setEnvFile != null) cfg.users);
    })

    (mkIf cfg.enable {
      environment.etc."bwai/README" = {
        text = ''
          Per-user bwai sandbox configs live here (generated by the
          bubblewrap-ai NixOS module).

            <user>.json         interactive sandbox policy
            <user>.agent.json   agent (Hermes) policy — stricter, auth
                                sockets stripped unless the policy opts in

          Use via the wrapped CLI (auto-selects the invoking user):
            bwai                -> /etc/bwai/<user>.json
            bwai-agent          -> /etc/bwai/<user>.agent.json
        '';
      };
    })
  ];
}
