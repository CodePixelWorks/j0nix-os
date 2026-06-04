{ ... }:
{
  # Program submodules under nix/user/programs/ are resolved dynamically via
  # mkProgramModule from settings.defaultHomePrograms or userSettings.<name>.homePrograms.
  # Do not add static imports here — they will not be loaded.
}
