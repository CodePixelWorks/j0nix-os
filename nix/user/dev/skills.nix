{
  lib,
  settings,
  ...
}:
let
  dev = settings.dev or { };
  ai = dev.ai or { };
  enabled = (dev.enable or true) && (ai.enable or true);
  cavemanEnabled = ai.caveman or true;
  cavemanSkillSource = ./skills/caveman;
  skillTargets = [
    ".agents/skills/caveman"
    ".claude/skills/caveman"
    ".codex/skills/caveman"
    ".kilo/skills/caveman"
  ];
  backupTargets = map (target: "${target}.backup") skillTargets;
  cleanupBackupScript = lib.concatMapStringsSep "\n" (
    backupTarget: ''
      backup_path="$HOME/${backupTarget}"
      target_path="''${backup_path%.backup}"

      if [ -L "$target_path" ] && [ -e "$backup_path" ]; then
        rm -rf "$backup_path"
      fi
    ''
  ) backupTargets;
in
lib.mkIf (enabled && cavemanEnabled) {
  home.file = builtins.listToAttrs (
    map (
      target: {
        name = target;
        value = {
          source = cavemanSkillSource;
        };
      }
    ) skillTargets
  );

  home.activation.cleanupCavemanSkillBackups = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    ${cleanupBackupScript}
  '';
}
