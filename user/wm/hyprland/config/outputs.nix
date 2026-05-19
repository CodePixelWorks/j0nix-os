{
  lib,
  pkgs,
  hyprlandCfg,
  profileDetails,
  sunshineUsesHeadlessOutput,
  sunshineUsesPhysicalOutput,
}:
let
  profileHeadlessOutput = profileDetails.hyprlandSunshineHeadlessOutput or null;
  profilePhysicalOutput = profileDetails.hyprlandSunshinePhysicalOutput or null;

  headlessOutputs =
    if hyprlandCfg ? headlessOutputs then
      hyprlandCfg.headlessOutputs
    else if sunshineUsesHeadlessOutput && profileHeadlessOutput != null then
      [ profileHeadlessOutput ]
    else
      [ ];
  headlessOutputIsEnabledByDefault =
    name:
    let
      matchingState = lib.findFirst (state: (state.name or "") == name) null (
        hyprlandCfg.initialOutputStates or [ ]
      );
    in
    if matchingState != null then matchingState.enabledByDefault or true else true;
  headlessOutputsWithBindings = map (
    output:
    if output ? bindIndex then
      output // { bindKey = if output.bindIndex == 10 then "0" else toString output.bindIndex; }
    else
      output
  ) headlessOutputs;
  headlessOutputNames = map (output: output.name or "") headlessOutputs;

  outputBindings =
    if hyprlandCfg ? outputBindings then
      hyprlandCfg.outputBindings
    else
      [ ];
  outputBindingsWithKeys = map (
    binding:
    binding // { bindKey = if binding.bindIndex == 10 then "0" else toString binding.bindIndex; }
  ) outputBindings;
  outputBindingNames = map (binding: binding.name or "") outputBindingsWithKeys;
  outputBindingIndices = map (binding: binding.bindIndex) outputBindingsWithKeys;

  toggleableOutputs =
    if hyprlandCfg ? toggleableOutputs then
      hyprlandCfg.toggleableOutputs
    else
      [ ];
  toggleableOutputsWithBindings = builtins.genList (
    idx:
    let
      output = builtins.elemAt toggleableOutputs idx;
      bindIndex = output.bindIndex or (idx + 1);
    in
    output
    // {
      inherit bindIndex;
      bindKey = if bindIndex == 10 then "0" else toString bindIndex;
    }
  ) (builtins.length toggleableOutputs);
  toggleableOutputNames = map (output: output.name or "") toggleableOutputsWithBindings;

  managedOutputsWithBindings =
    toggleableOutputsWithBindings
    ++ (builtins.filter (output: output ? bindIndex) headlessOutputsWithBindings);
  managedOutputBindIndices = map (output: output.bindIndex) managedOutputsWithBindings;

  initialOutputStates =
    if hyprlandCfg ? initialOutputStates then
      hyprlandCfg.initialOutputStates
    else
      lib.optionals (sunshineUsesHeadlessOutput && profileHeadlessOutput != null) [
        {
          name = profileHeadlessOutput.name;
          enabledByDefault = false;
          mode = profileHeadlessOutput.mode or "2880x1800@60";
          position = profileHeadlessOutput.position or "10000x10000";
          scale = profileHeadlessOutput.scale or 1;
        }
      ]
      ++ lib.optionals (sunshineUsesPhysicalOutput && profilePhysicalOutput != null) [
        {
          name = profilePhysicalOutput.name;
          enabledByDefault = false;
          mode = profilePhysicalOutput.mode or "1920x1080@60";
          position = profilePhysicalOutput.position or "0x4000";
          scale = profilePhysicalOutput.scale or 1;
        }
      ];
  initialOutputStateNames = map (output: output.name or "") initialOutputStates;
in
{
  inherit headlessOutputs headlessOutputsWithBindings headlessOutputNames;
  headlessOutputsAutoEnsure = builtins.any (
    output: headlessOutputIsEnabledByDefault (output.name or "")
  ) headlessOutputs;
  headlessOutputsJson = pkgs.writeText "hyprland-headless-outputs.json" (
    builtins.toJSON headlessOutputs
  );

  inherit
    outputBindings
    outputBindingsWithKeys
    outputBindingNames
    outputBindingIndices
    ;
  outputBindingsJson = pkgs.writeText "hyprland-output-bindings.json" (
    builtins.toJSON outputBindingsWithKeys
  );

  inherit initialOutputStates initialOutputStateNames;
  initialOutputStatesJson = pkgs.writeText "hyprland-initial-output-states.json" (
    builtins.toJSON initialOutputStates
  );

  inherit toggleableOutputs toggleableOutputsWithBindings toggleableOutputNames;
  inherit managedOutputsWithBindings managedOutputBindIndices;
  toggleableOutputsJson = pkgs.writeText "hyprland-toggleable-outputs.json" (
    builtins.toJSON managedOutputsWithBindings
  );
}
