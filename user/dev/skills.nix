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
}
