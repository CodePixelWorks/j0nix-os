{
  lib,
  pkgs,
  hyprlandCfg,
  profileDetails,
  sunshineUsesHeadlessOutput,
  sunshineUsesPhysicalOutput,
}:
let
  profileUnifiedOutputs = profileDetails.hyprlandOutputs or [ ];
  profileOutputsWithBindIndex = builtins.filter (
    output: (output.outputBinding or (output.toggleable or false)) && (output ? bindIndex)
  ) profileUnifiedOutputs;
  profileMonitorRulesBase =
    if profileDetails ? hyprlandMonitors then
      profileDetails.hyprlandMonitors
    else
      map
        (output: {
          output = output.name;
          mode = output.mode or "preferred";
          position = output.position or "auto";
          scale = output.scale or 1;
        })
        (builtins.filter (output: output.monitorRule or true) profileUnifiedOutputs);
  profileHeadlessOutput = profileDetails.hyprlandSunshineHeadlessOutput or null;
  profilePhysicalOutput = profileDetails.hyprlandSunshinePhysicalOutput or null;
  profileOutputBindingsBase =
    if profileDetails ? hyprlandOutputBindingsBase then
      profileDetails.hyprlandOutputBindingsBase
    else
      map
        (output:
          builtins.removeAttrs output [
            "id"
            "mode"
            "position"
            "scale"
            "enabledByDefault"
            "focusOnEnable"
            "monitorRule"
            "toggleable"
            "workspaceHandoff"
          ])
        profileOutputsWithBindIndex;
  profileInitialOutputStatesBase =
    if profileDetails ? hyprlandInitialOutputStatesBase then
      profileDetails.hyprlandInitialOutputStatesBase
    else
      map
        (output:
          {
            inherit (output) name;
            enabledByDefault = output.enabledByDefault or true;
            mode = output.mode or "preferred";
            position = output.position or "auto";
            scale = output.scale or 1;
          }
          // lib.optionalAttrs (output ? id) { inherit (output) id; }
          // lib.optionalAttrs (output ? description) { inherit (output) description; }
          // lib.optionalAttrs (output ? match) { inherit (output) match; })
        profileUnifiedOutputs;
  profileToggleableOutputsBase =
    if profileDetails ? hyprlandToggleableOutputsBase then
      profileDetails.hyprlandToggleableOutputsBase
    else
      builtins.filter (output: output.toggleable or false) profileUnifiedOutputs;

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
      profileOutputBindingsBase
      ++ lib.optionals (sunshineUsesPhysicalOutput && profilePhysicalOutput != null) [
        {
          name = profilePhysicalOutput.name;
          description = profilePhysicalOutput.description or "";
          bindIndex = profilePhysicalOutput.bindIndex;
        }
      ]
      ++ lib.optionals (sunshineUsesHeadlessOutput && profileHeadlessOutput != null) [
        {
          name = profileHeadlessOutput.name;
          description = profileHeadlessOutput.description or "";
          bindIndex = profileHeadlessOutput.bindIndex;
        }
      ];
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
      profileToggleableOutputsBase
      ++ lib.optionals (sunshineUsesPhysicalOutput && profilePhysicalOutput != null) [
        profilePhysicalOutput
      ];
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
    let
      configured =
        if hyprlandCfg ? initialOutputStates then
          hyprlandCfg.initialOutputStates
        else
          profileInitialOutputStatesBase
          ++ lib.optionals (sunshineUsesHeadlessOutput && profileHeadlessOutput != null) [
            {
              name = profileHeadlessOutput.name;
              enabledByDefault = false;
              mode = profileHeadlessOutput.mode or "2880x1800@60";
              position = profileHeadlessOutput.position or "10000x10000";
              scale = profileHeadlessOutput.scale or 1;
            }
          ];
    in
    if configured != [ ] then
      configured
    else
      map (output: {
        name = output.name or "";
        enabledByDefault = output.enabledByDefault or true;
        mode = output.mode or "preferred";
        position = output.position or "auto";
        scale = output.scale or 1;
      }) toggleableOutputs;
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
  inherit profileMonitorRulesBase;
  initialOutputStatesJson = pkgs.writeText "hyprland-initial-output-states.json" (
    builtins.toJSON initialOutputStates
  );

  inherit toggleableOutputs toggleableOutputsWithBindings toggleableOutputNames;
  inherit managedOutputsWithBindings managedOutputBindIndices;
  toggleableOutputsJson = pkgs.writeText "hyprland-toggleable-outputs.json" (
    builtins.toJSON managedOutputsWithBindings
  );
}
