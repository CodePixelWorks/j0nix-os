{
  lib,
  pkgs,
  hyprctlExec,
  toggleableOutputsJson,
  initialOutputStatesJson,
  outputBindingsJson,
  headlessOutputsJson,
  hyprlandRuntimeMonitorConfigPath,
  homeDirectory,
}:
let
  monitorStateScript = pkgs.writeShellScriptBin "wm-monitor" ''
    set -eu

    hyprctl_bin="${hyprctlExec}"
    jq_bin="${pkgs.jq}/bin/jq"
    flock_bin="${pkgs.util-linux}/bin/flock"
    outputs_json=${lib.escapeShellArg toggleableOutputsJson}
    initial_states_json=${lib.escapeShellArg initialOutputStatesJson}
    bindings_json=${lib.escapeShellArg outputBindingsJson}
    headless_outputs_json=${lib.escapeShellArg headlessOutputsJson}
    runtime_config_path=${lib.escapeShellArg hyprlandRuntimeMonitorConfigPath}
    runtime_dir="''${XDG_RUNTIME_DIR:-}"
    if [ -n "$runtime_dir" ] && [ -d "$runtime_dir" ] && [ -w "$runtime_dir" ]; then
      state_dir="$runtime_dir/hyprland-monitor-state"
    else
      state_home="''${XDG_STATE_HOME:-$HOME/.local/state}"
      state_dir="$state_home/hyprland-monitor-state"
    fi
    command="''${1:-}"
    output_name="''${2:-}"

    [ -x "$hyprctl_bin" ] || exit 0
    [ -x "$jq_bin" ] || exit 0
    mkdir -p "$state_dir"
    lock_file="$state_dir/runtime-monitors.lock"

    usage() {
      echo "usage: wm-monitor <on|off|toggle|restore|status|workspace-to|focused-workspaces-to|list|discover|enable-discovered|suggest|prompt-new|sync-live|sync-defaults|watch> [output-name]" >&2
      exit 2
    }

    acquire_runtime_lock() {
      exec 8>"$lock_file"
      "$flock_bin" -x 8
    }

    release_runtime_lock() {
      "$flock_bin" -u 8 >/dev/null 2>&1 || true
      exec 8>&-
    }

    with_runtime_lock() {
      local rc
      acquire_runtime_lock
      set +e
      "$@"
      rc=$?
      set -e
      release_runtime_lock
      return "$rc"
    }

    sanitize_name() {
      printf '%s' "$1" | tr -c '[:alnum:]._-' '_'
    }

    state_prefix() {
      printf '%s/%s' "$state_dir" "$(sanitize_name "$1")"
    }

    load_output_config() {
      local name="$1"
      "$jq_bin" -ce --arg name "$name" '.[] | select(.name == $name)' "$outputs_json"
    }

    load_output_binding() {
      local name="$1"
      "$jq_bin" -ce --arg name "$name" '.[] | select(.name == $name)' "$bindings_json"
    }

    output_is_headless() {
      local name="$1"
      "$jq_bin" -e --arg name "$name" '.[] | select(.name == $name)' "$headless_outputs_json" >/dev/null 2>&1
    }

    ensure_headless_output() {
      local name="$1"
      output_is_headless "$name" || return 0
      if ! "$hyprctl_bin" -j monitors all | "$jq_bin" -e --arg name "$name" '.[] | select(.name == $name)' >/dev/null 2>&1; then
        "$hyprctl_bin" output create headless "$name" >/dev/null 2>&1 || true
        for _ in $(seq 1 50); do
          if "$hyprctl_bin" -j monitors all | "$jq_bin" -e --arg name "$name" '.[] | select(.name == $name)' >/dev/null 2>&1; then
            break
          fi
          sleep 0.1
        done
      fi
    }

    output_is_known() {
      local name="$1"
      "$jq_bin" -e --arg name "$name" '.[] | select(.name == $name)' "$bindings_json" >/dev/null 2>&1
    }

    require_output_name() {
      [ -n "$output_name" ] || usage
    }

    get_output_field() {
      local output_json="$1"
      local query="$2"
      printf '%s' "$output_json" | "$jq_bin" -r "$query"
    }

    lua_string() {
      "$jq_bin" -Rn -r --arg value "$1" '$value | @json'
    }

    render_monitor_enabled() {
      local name="$1"
      local mode="$2"
      local position="$3"
      local scale="$4"
      printf 'hl.monitor({ output = %s, disabled = false, mode = %s, position = %s, scale = %s })\n' \
        "$(lua_string "$name")" \
        "$(lua_string "$mode")" \
        "$(lua_string "$position")" \
        "$(lua_string "$scale")"
    }

    render_monitor_disabled() {
      local name="$1"
      printf 'hl.monitor({ output = %s, disabled = true })\n' "$(lua_string "$name")"
    }

    apply_monitor_enabled() {
      local name="$1"
      local mode="$2"
      local position="$3"
      local scale="$4"
      "$hyprctl_bin" eval "$(render_monitor_enabled "$name" "$mode" "$position" "$scale")" >/dev/null 2>&1 || true
    }

    apply_monitor_disabled() {
      local name="$1"
      "$hyprctl_bin" eval "$(render_monitor_disabled "$name")" >/dev/null 2>&1 || true
    }

    write_runtime_header() {
      echo "-- ------------------------------------------------------------------"
      echo "-- Runtime Monitor Overrides"
      echo "-- ------------------------------------------------------------------"
      echo "-- Managed by wm-monitor. This file intentionally persists current"
      echo "-- toggleable output state across Hyprland reloads."
    }

    output_is_active() {
      local name="$1"
      "$hyprctl_bin" -j monitors | "$jq_bin" -e --arg name "$name" '.[] | select(.name == $name and (.disabled // false) == false)' >/dev/null 2>&1
    }

    list_unknown_active_monitors() {
      "$hyprctl_bin" -j monitors all \
        | "$jq_bin" -c --slurpfile bindings "$bindings_json" '
            .[] as $monitor
            | select(($monitor.disabled // false) == false and ($monitor.name // "") != "")
            | select(((($bindings[0] // []) | map(.name)) | index($monitor.name)) == null)
            | $monitor
          '
    }

    get_live_monitor_json() {
      local name="$1"
      "$hyprctl_bin" -j monitors all | "$jq_bin" -ce --arg name "$name" '.[] | select(.name == $name and (.disabled // false) == false)'
    }

    monitor_spec_from_declared_output() {
      local output_json="$1"
      local name mode position scale

      name="$(printf '%s' "$output_json" | "$jq_bin" -r '.name // empty')"
      mode="$(printf '%s' "$output_json" | "$jq_bin" -r '.mode // "preferred"')"
      position="$(printf '%s' "$output_json" | "$jq_bin" -r '.position // "auto"')"
      scale="$(printf '%s' "$output_json" | "$jq_bin" -r '(.scale // 1) | tostring')"
      [ -n "$name" ] || return 1
      printf '%s,%s,%s,%s\n' "$name" "$mode" "$position" "$scale"
    }

    monitor_spec_from_live_or_declared_output() {
      local output_json="$1"
      local name monitor_json mode position scale

      name="$(printf '%s' "$output_json" | "$jq_bin" -r '.name // empty')"
      [ -n "$name" ] || return 1
      monitor_json="$(get_live_monitor_json "$name" 2>/dev/null || true)"

      if [ -n "$monitor_json" ]; then
        mode="$(printf '%s' "$monitor_json" | "$jq_bin" -r '"\(.width)x\(.height)@\((.refreshRate // 60) | tostring)"')"
        position="$(printf '%s' "$monitor_json" | "$jq_bin" -r '"\((.x // 0) | floor)x\((.y // 0) | floor)"')"
        scale="$(printf '%s' "$monitor_json" | "$jq_bin" -r '(.scale // 1) | tostring')"
        printf '%s,%s,%s,%s\n' "$name" "$mode" "$position" "$scale"
      else
        monitor_spec_from_declared_output "$output_json"
      fi
    }

    save_output_runtime_spec() {
      local output_json="$1"
      local prefix="$2"
      local current_spec _name output_mode output_position output_scale

      current_spec="$(monitor_spec_from_live_or_declared_output "$output_json")" || return 0
      IFS=, read -r _name output_mode output_position output_scale <<EOF
    $current_spec
    EOF
      printf '%s\n' "$output_mode" >"$prefix.mode"
      printf '%s\n' "$output_position" >"$prefix.position"
      printf '%s\n' "$output_scale" >"$prefix.scale"
    }

    read_saved_or_declared_output_field() {
      local prefix="$1"
      local file_suffix="$2"
      local output_json="$3"
      local query="$4"
      local file_path="$prefix.$file_suffix"

      if [ -f "$file_path" ]; then
        cat "$file_path" 2>/dev/null || true
      else
        get_output_field "$output_json" "$query"
      fi
    }

    sync_default_monitor_overrides_locked() {
      local tmp_file output name enabled monitor_line

      mkdir -p "$(dirname "$runtime_config_path")"
      tmp_file="$(mktemp "$(dirname "$runtime_config_path")/.runtime-monitors.lua.XXXXXX")"
      {
        write_runtime_header
        "$jq_bin" -c '.[]' "$initial_states_json" | while IFS= read -r output; do
          name="$(printf '%s' "$output" | "$jq_bin" -r '.name // empty')"
          [ -n "$name" ] || continue
          enabled="$(printf '%s' "$output" | "$jq_bin" -r 'if (.enabledByDefault == false) then "0" else "1" end')"

          if [ "$enabled" = "1" ]; then
            monitor_line="$(monitor_spec_from_declared_output "$output")"
          else
            monitor_line="$name,disable"
          fi

          IFS=, read -r name mode position scale <<EOF
    $monitor_line
    EOF
          if [ "$enabled" = "1" ]; then
            render_monitor_enabled "$name" "$mode" "$position" "$scale"
          else
            render_monitor_disabled "$name"
          fi
        done
      } >"$tmp_file"
      mv -f "$tmp_file" "$runtime_config_path"

      if "$hyprctl_bin" -j monitors all >/dev/null 2>&1; then
        "$jq_bin" -c '.[]' "$initial_states_json" | while IFS= read -r output; do
          name="$(printf '%s' "$output" | "$jq_bin" -r '.name // empty')"
          enabled="$(printf '%s' "$output" | "$jq_bin" -r 'if (.enabledByDefault == false) then "0" else "1" end')"
          monitor_line="$(monitor_spec_from_declared_output "$output")"
          [ -n "$name" ] || continue

          if [ "$enabled" = "1" ] && output_is_headless "$name"; then
            ensure_headless_output "$name"
          fi

          IFS=, read -r _name mode position scale <<EOF
    $monitor_line
    EOF
          if [ "$enabled" = "1" ]; then
            apply_monitor_enabled "$name" "$mode" "$position" "$scale"
          else
            apply_monitor_disabled "$name"
          fi
        done
      fi
    }

    sync_default_monitor_overrides() {
      with_runtime_lock sync_default_monitor_overrides_locked
    }

    describe_monitor_json() {
      local monitor_json="$1"
      printf '%s' "$monitor_json" \
        | "$jq_bin" -r '
            if (.description // "") != "" then
              .description
            else
              ([.make // "", .model // ""] | map(select(. != "")) | join(" "))
            end
          '
    }

    parse_mode_dimensions() {
      local mode="$1"
      printf '%s\n' "$mode" | sed -n 's/^\([0-9]\+\)x\([0-9]\+\)@.*$/\1 \2/p'
    }

    compute_unknown_monitor_position() {
      local width="$1"
      local height="$2"
      local left_x bottom_y pos_x pos_y

      read -r left_x bottom_y <<EOF
    $("$hyprctl_bin" -j monitors | "$jq_bin" -r '
      [ .[] | select((.disabled // false) == false) | {
          x: (.x // 0),
          y: (.y // 0),
          width: (.width // 0),
          height: (.height // 0),
          scale: (.scale // 1)
        } ] as $monitors
      | if ($monitors | length) == 0 then
          "-1 0"
        else
          [
            ($monitors | map(.x) | min),
            ($monitors | map(.y + ((.height / .scale) | floor)) | max)
          ]
          | @tsv
        end
    ')
    EOF

      [ -n "''${left_x:-}" ] || left_x=0
      [ -n "''${bottom_y:-}" ] || bottom_y=0
      pos_x=$((left_x - width))
      pos_y=$((bottom_y - height))
      printf '%sx%s\n' "$pos_x" "$pos_y"
    }

    get_unknown_monitor_json() {
      local name="$1"
      "$hyprctl_bin" -j monitors all | "$jq_bin" -ce --arg name "$name" '.[] | select(.name == $name)'
    }

    unknown_monitor_mode() {
      local monitor_json="$1"
      printf '%s' "$monitor_json" | "$jq_bin" -r '
        if (.disabled // false) == false and (.width // 0) > 0 and (.height // 0) > 0 then
          "\(.width)x\(.height)@\((.refreshRate // 60) | tostring)"
        else
          (.availableModes[0] // "1920x1080@60.00Hz")
        end
      ' | sed 's/Hz$//'
    }

    unknown_monitor_scale() {
      printf '1\n'
    }

    unknown_monitor_position() {
      local monitor_json="$1"
      local mode width height dims

      mode="$(unknown_monitor_mode "$monitor_json")"
      dims="$(parse_mode_dimensions "$mode" || true)"
      width="$(printf '%s' "$dims" | awk '{print $1}')"
      height="$(printf '%s' "$dims" | awk '{print $2}')"

      if [ -z "''${width:-}" ] || [ -z "''${height:-}" ]; then
        printf '%s\n' "-1920x0"
        return 0
      fi

      compute_unknown_monitor_position "$width" "$height"
    }

    list_unknown_monitors() {
      "$hyprctl_bin" -j monitors all \
        | "$jq_bin" -r --slurpfile bindings "$bindings_json" '
            .[] as $monitor
            | select(($monitor.name // "") != "")
            | select(((($bindings[0] // []) | map(.name)) | index($monitor.name)) == null)
            | [
                $monitor.name,
                (if ($monitor.disabled // false) then "disabled" else "active" end),
                (if ($monitor.description // "") != "" then $monitor.description else ([$monitor.make // "", $monitor.model // ""] | map(select(. != "")) | join(" ")) end),
                (
                  if ($monitor.disabled // false) == false and ($monitor.width // 0) > 0 and ($monitor.height // 0) > 0 then
                    "\($monitor.width)x\($monitor.height)@\(($monitor.refreshRate // 60) | tostring)"
                  else
                    ($monitor.availableModes[0] // "1920x1080@60.00Hz")
                  end
                ),
                ""
              ]
            | @tsv
          ' \
        | while IFS=$'\t' read -r name state description mode _; do
            [ -n "$name" ] || continue
            position="$(unknown_monitor_position "$(get_unknown_monitor_json "$name")")"
            printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$state" "$description" "$(printf '%s' "$mode" | sed 's/Hz$//')" "$position"
          done
    }

    enable_unknown_monitor() {
      local name="$1"
      local monitor_json mode position scale

      monitor_json="$(get_unknown_monitor_json "$name")" || {
        echo "Unknown monitor: $name" >&2
        exit 1
      }

      if output_is_known "$name"; then
        echo "Monitor $name is already managed. Use wm-monitor on/off/toggle instead." >&2
        exit 1
      fi

      mode="$(unknown_monitor_mode "$monitor_json")"
      position="$(unknown_monitor_position "$monitor_json")"
      scale="$(unknown_monitor_scale)"

      apply_monitor_enabled "$name" "$mode" "$position" "$scale"
      wait_for_output_state "$name" active
      printf '%s enabled temporarily at %s with %s scale %s\n' "$name" "$position" "$mode" "$scale"
    }

    suggest_unknown_monitor_config() {
      local name="$1"
      local monitor_json description mode position

      monitor_json="$(get_unknown_monitor_json "$name")" || {
        echo "Unknown monitor: $name" >&2
        exit 1
      }

      description="$(describe_monitor_json "$monitor_json")"
      mode="$(unknown_monitor_mode "$monitor_json")"
      position="$(unknown_monitor_position "$monitor_json")"

      cat <<EOF
    # Suggested settings.nix snippet for $name
    # Description: $description

    {
      name = "$name";
      enabledByDefault = false;
      mode = "$mode";
      position = "$position";
      scale = 1;
    }
    EOF
    }

    prompt_new_monitor_dialog() {
      local mode unknown_lines unknown_signature signature_file yad_bin nwg_displays_bin wl_copy_bin
      local selected_name action_rc snippet_file

      mode="''${1:-interactive}"
      signature_file="$state_dir/new-monitor-dialog.signature"
      yad_bin="$(command -v yad || true)"
      nwg_displays_bin="$(command -v nwg-displays || true)"
      wl_copy_bin="$(command -v wl-copy || true)"

      unknown_lines="$(list_unknown_monitors || true)"
      if [ -z "$unknown_lines" ]; then
        rm -f "$signature_file"
        return 0
      fi

      unknown_signature="$(
        printf '%s\n' "$unknown_lines" \
          | cut -f1 \
          | sort \
          | tr '\n' ',' \
          | sed 's/,$//'
      )"

      if [ "$mode" = "--auto" ]; then
        if [ -f "$signature_file" ] && [ "$(cat "$signature_file" 2>/dev/null || true)" = "$unknown_signature" ]; then
          return 0
        fi
        printf '%s\n' "$unknown_signature" >"$signature_file"
      fi

      if [ -z "$yad_bin" ]; then
        if [ "$mode" != "--auto" ]; then
          printf '%s\n' "$unknown_lines"
        fi
        return 0
      fi

      if selected_name="$(
        printf '%s\n' "$unknown_lines" | "$yad_bin" \
          --list \
          --title="New Monitor Detected" \
          --text="Select how to handle the newly detected monitor." \
          --column="Name" \
          --column="State" \
          --column="Description" \
          --column="Suggested Mode" \
          --column="Suggested Position" \
          --separator=$'\t' \
          --print-column=1 \
          --button="Enable Temporarily:0" \
          --button="Show Suggested Nix Snippet:2" \
          --button="Open nwg-displays:3" \
          --button="Cancel:1"
      )"; then
        action_rc=0
      else
        action_rc=$?
      fi

      [ -n "$selected_name" ] || return 0

      case "$action_rc" in
        0)
          enable_unknown_monitor "$selected_name"
          sync_runtime_monitor_overrides
          ;;
        2)
          snippet_file="$(mktemp)"
          suggest_unknown_monitor_config "$selected_name" >"$snippet_file"
          if [ -n "$wl_copy_bin" ]; then
            "$wl_copy_bin" <"$snippet_file" >/dev/null 2>&1 || true
          fi
          "$yad_bin" --text-info --title="Suggested Nix Snippet" --filename="$snippet_file" --width=760 --height=420
          rm -f "$snippet_file"
          ;;
        3)
          if [ -n "$nwg_displays_bin" ]; then
            "$nwg_displays_bin" >/dev/null 2>&1 &
          fi
          ;;
      esac
    }

    wait_for_output_state() {
      local name="$1"
      local desired_state="$2"

      for _ in $(seq 1 50); do
        if [ "$desired_state" = "active" ]; then
          output_is_active "$name" && return 0
        else
          output_is_active "$name" || return 0
        fi
        sleep 0.1
      done

      return 0
    }

    save_output_state() {
      local name="$1"
      local prefix="$2"
      local output_json="$3"

      "$hyprctl_bin" -j workspaces \
        | "$jq_bin" -r --arg output "$name" '.[] | select(.monitor == $output and (.id // -1) > 0 and (.name // "") != "") | [.name, .monitor] | @tsv' >"$prefix.workspaces.tmp"
      mv -f "$prefix.workspaces.tmp" "$prefix.workspaces"
      "$hyprctl_bin" -j monitors \
        | "$jq_bin" -r --arg output "$name" '.[] | select(.name == $output) | .activeWorkspace.name // empty' >"$prefix.active-workspace"
      "$hyprctl_bin" -j monitors \
        | "$jq_bin" -r '.[] | select(.focused == true) | .name // empty' >"$prefix.focused-monitor"
      save_output_runtime_spec "$output_json" "$prefix"
    }

    move_workspace() {
      local workspace_name="$1"
      local target_monitor="$2"
      [ -n "$workspace_name" ] || return 0
      [ -n "$target_monitor" ] || return 0
      "$hyprctl_bin" dispatch moveworkspacetomonitor "$workspace_name $target_monitor" >/dev/null 2>&1 || true
    }

    get_monitor_active_workspace() {
      local name="$1"
      "$hyprctl_bin" -j monitors | "$jq_bin" -r --arg name "$name" '.[] | select(.name == $name) | .activeWorkspace.name // empty'
    }

    get_focused_monitor() {
      "$hyprctl_bin" -j monitors | "$jq_bin" -r '.[] | select(.focused == true) | .name // empty'
    }

    pick_handoff_monitor() {
      local source_monitor="$1"
      local preferred_monitor="$2"

      if [ -n "$preferred_monitor" ] && [ "$preferred_monitor" != "$source_monitor" ] && output_is_active "$preferred_monitor"; then
        printf '%s\n' "$preferred_monitor"
        return 0
      fi

      "$hyprctl_bin" -j monitors         | "$jq_bin" -r --arg source "$source_monitor" '.[] | select((.disabled // false) == false and (.name // "") != "" and .name != $source) | .name'         | head -n 1
    }

    focus_monitor() {
      local name="$1"
      [ -n "$name" ] || return 0
      "$hyprctl_bin" dispatch focusmonitor "$name" >/dev/null 2>&1 || true
    }

    activate_workspace_on_monitor() {
      local monitor_name="$1"
      local workspace_name="$2"

      [ -n "$monitor_name" ] || return 0
      [ -n "$workspace_name" ] || return 0

      focus_monitor "$monitor_name"
      "$hyprctl_bin" dispatch workspace "$workspace_name" >/dev/null 2>&1 || true
    }

    move_monitor_workspaces_to_target() {
      local source_monitor="$1"
      local target_monitor="$2"
      local active_workspace=""

      [ -n "$source_monitor" ] || return 0
      [ -n "$target_monitor" ] || return 0
      [ "$source_monitor" = "$target_monitor" ] && return 0

      active_workspace="$(get_monitor_active_workspace "$source_monitor")"

      while IFS= read -r workspace_name; do
        [ -n "$workspace_name" ] || continue
        [ "$workspace_name" = "$active_workspace" ] && continue
        move_workspace "$workspace_name" "$target_monitor"
      done < <(
        "$hyprctl_bin" -j workspaces \
          | "$jq_bin" -r --arg output "$source_monitor" '.[] | select(.monitor == $output and (.id // -1) > 0 and (.name // "") != "") | .name'
      )

      if [ -n "$active_workspace" ]; then
        move_workspace "$active_workspace" "$target_monitor"
        activate_workspace_on_monitor "$target_monitor" "$active_workspace"
      else
        focus_monitor "$target_monitor"
      fi
    }

    move_active_workspace_to_output() {
      local target_monitor="$1"
      local workspace_name

      workspace_name="$("$hyprctl_bin" -j activeworkspace | "$jq_bin" -r '.name // empty')"
      [ -n "$workspace_name" ] || return 0
      move_workspace "$workspace_name" "$target_monitor"
      activate_workspace_on_monitor "$target_monitor" "$workspace_name"
    }

    move_other_monitors_workspaces_to_target() {
      local target_monitor="$1"

      [ -n "$target_monitor" ] || return 0

      "$hyprctl_bin" -j monitors         | "$jq_bin" -r --arg target "$target_monitor" '.[] | select((.disabled // false) == false and (.name // "") != "" and .name != $target) | .name'         | while IFS= read -r source_monitor; do
            [ -n "$source_monitor" ] || continue
            move_monitor_workspaces_to_target "$source_monitor" "$target_monitor"
          done

      focus_monitor "$target_monitor"
    }

    ensure_output_ready_for_workspace_move() {
      local target_monitor="$1"
      local output_json prefix

      [ -n "$target_monitor" ] || return 0
      output_json="$(load_output_config "$target_monitor" 2>/dev/null || true)"
      [ -n "$output_json" ] || return 0

      if ! output_is_active "$target_monitor"; then
        prefix="$(state_prefix "$target_monitor")"
        enable_output "$output_json" "$target_monitor" "$prefix"
        sync_runtime_monitor_overrides
      fi
    }

    disable_output() {
      local output_json="$1"
      local name="$2"
      local prefix="$3"
      local handoff_enabled target_monitor

      handoff_enabled="$(get_output_field "$output_json" 'if (.workspaceHandoff.enable // false) then "1" else "0" end')"
      target_monitor="$(get_output_field "$output_json" '.workspaceHandoff.targetMonitor // ""')"
      target_monitor="$(pick_handoff_monitor "$name" "$target_monitor")"
      printf '%s\n' "$target_monitor" >"$prefix.target-monitor"

      if output_is_active "$name"; then
        save_output_state "$name" "$prefix" "$output_json"

        if [ "$handoff_enabled" = "1" ] && [ -n "$target_monitor" ]; then
          move_monitor_workspaces_to_target "$name" "$target_monitor"
        fi
      fi

      apply_monitor_disabled "$name"
      wait_for_output_state "$name" inactive
    }

    enable_output() {
      local output_json="$1"
      local name="$2"
      local prefix="$3"
      local output_mode output_position output_scale focus_on_enable focused_monitor active_workspace

      output_mode="$(read_saved_or_declared_output_field "$prefix" mode "$output_json" '.mode // "preferred"')"
      output_position="$(read_saved_or_declared_output_field "$prefix" position "$output_json" '.position // "auto"')"
      output_scale="$(read_saved_or_declared_output_field "$prefix" scale "$output_json" '(.scale // 1) | tostring')"
      focus_on_enable="$(get_output_field "$output_json" 'if (.focusOnEnable // false) then "1" else "0" end')"

       if output_is_headless "$name" && ! "$hyprctl_bin" -j monitors all | "$jq_bin" -e --arg name "$name" '.[] | select(.name == $name)' >/dev/null 2>&1; then
        "$hyprctl_bin" output create headless "$name" >/dev/null 2>&1 || true
        for _ in $(seq 1 50); do
          if "$hyprctl_bin" -j monitors all | "$jq_bin" -e --arg name "$name" '.[] | select(.name == $name)' >/dev/null 2>&1; then
            break
          fi
          sleep 0.1
        done
      fi

      apply_monitor_enabled "$name" "$output_mode" "$output_position" "$output_scale"
      wait_for_output_state "$name" active

      if [ -f "$prefix.workspaces" ]; then
        active_workspace="$(cat "$prefix.active-workspace" 2>/dev/null || true)"
        while IFS=$'\t' read -r workspace_name _; do
          [ -n "$workspace_name" ] || continue
          [ "$workspace_name" = "$active_workspace" ] && continue
          move_workspace "$workspace_name" "$name"
        done <"$prefix.workspaces"

        if [ -n "$active_workspace" ]; then
          move_workspace "$active_workspace" "$name"
          activate_workspace_on_monitor "$name" "$active_workspace"
        else
          focus_monitor "$name"
        fi
      fi

      focused_monitor="$(cat "$prefix.focused-monitor" 2>/dev/null || true)"
      if [ "$focus_on_enable" = "1" ] || [ "$focused_monitor" = "$name" ]; then
        focus_monitor "$name"
      elif [ -n "$focused_monitor" ]; then
        focus_monitor "$focused_monitor"
      fi
    }

    restore_output_state() {
      local output_json="$1"
      local name="$2"
      local prefix="$3"

      enable_output "$output_json" "$name" "$prefix"
      rm -f "$prefix.workspaces" "$prefix.active-workspace" "$prefix.focused-monitor" "$prefix.mode" "$prefix.position" "$prefix.scale" "$prefix.target-monitor"
    }

    monitor_status() {
      local output_json="$1"
      local name="$2"
      local prefix="$3"
      local active state

      if output_is_active "$name"; then
        active="active"
      else
        active="disabled"
      fi

      if [ -f "$prefix.workspaces" ]; then
        state="saved-state"
      else
        state="no-saved-state"
      fi

      echo "$name $active $state"
    }

    monitor_list() {
      "$jq_bin" -r '.[] | [.bindIndex, .name, (.description // "")] | @tsv' "$bindings_json" \
        | while IFS=$'\t' read -r bind_index name description; do
            [ -n "$name" ] || continue
            if output_is_active "$name"; then
              active="active"
            else
              active="disabled"
            fi
            printf '%s\t%s\t%s\t%s\n' "$bind_index" "$name" "$description" "$active"
          done
    }

    sync_runtime_monitor_overrides_locked() {
      local tmp_file monitor_line output name unknown_monitor_json unknown_name unknown_spec

      mkdir -p "$(dirname "$runtime_config_path")"
      tmp_file="$(mktemp "$(dirname "$runtime_config_path")/.runtime-monitors.lua.XXXXXX")"
      {
        write_runtime_header
        "$jq_bin" -c '.[]' "$outputs_json" | while IFS= read -r output; do
          name="$(printf '%s' "$output" | "$jq_bin" -r '.name // empty')"
          [ -n "$name" ] || continue

          if output_is_active "$name"; then
            monitor_line="$(monitor_spec_from_live_or_declared_output "$output")"
          else
            monitor_line="''${name},disable"
          fi

          if output_is_active "$name"; then
            IFS=, read -r _name mode position scale <<EOF
    $monitor_line
    EOF
            render_monitor_enabled "$name" "$mode" "$position" "$scale"
          else
            render_monitor_disabled "$name"
          fi
        done

        list_unknown_active_monitors | while IFS= read -r unknown_monitor_json; do
          unknown_name="$(printf '%s' "$unknown_monitor_json" | "$jq_bin" -r '.name // empty')"
          [ -n "$unknown_name" ] || continue
          unknown_spec="$(printf '%s' "$unknown_monitor_json" | "$jq_bin" -r '"\(.name),preferred,\((.x // 0) | floor)x\((.y // 0) | floor),\((.scale // 1) | tostring)"')"
          IFS=, read -r _name mode position scale <<EOF
    $unknown_spec
    EOF
          render_monitor_enabled "$unknown_name" "$mode" "$position" "$scale"
        done
      } >"$tmp_file"
      mv -f "$tmp_file" "$runtime_config_path"
    }

    sync_runtime_monitor_overrides() {
      with_runtime_lock sync_runtime_monitor_overrides_locked
    }

    watch_monitor_events() {
      while :; do
        sync_runtime_monitor_overrides || true
        prompt_new_monitor_dialog --auto || true
        sleep 2
      done
    }

    case "$command" in
      list)
        monitor_list
        exit 0
        ;;
      sync-live)
        sync_runtime_monitor_overrides
        exit 0
        ;;
      sync-defaults)
        sync_default_monitor_overrides
        exit 0
        ;;
      watch)
        watch_monitor_events
        exit 0
        ;;
      prompt-new)
        prompt_new_monitor_dialog "$output_name"
        exit 0
        ;;
      discover)
        list_unknown_monitors
        exit 0
        ;;
      enable-discovered|suggest)
        require_output_name
        ;;
      on|off|toggle|restore|status)
        require_output_name
        output_json="$(load_output_config "$output_name")" || {
          echo "Unknown managed output: $output_name" >&2
          exit 1
        }
        prefix="$(state_prefix "$output_name")"
        ;;
      workspace-to|focused-workspaces-to)
        require_output_name
        if [ -s "$bindings_json" ]; then
          load_output_binding "$output_name" >/dev/null 2>&1 || {
            echo "Unknown output binding: $output_name" >&2
            exit 1
          }
        fi
        ;;
      *)
        usage
        ;;
    esac

    case "$command" in
      on)
        enable_output "$output_json" "$output_name" "$prefix"
        sync_runtime_monitor_overrides
        ;;
      off)
        disable_output "$output_json" "$output_name" "$prefix"
        sync_runtime_monitor_overrides
        ;;
      toggle)
        if output_is_active "$output_name"; then
          disable_output "$output_json" "$output_name" "$prefix"
        else
          enable_output "$output_json" "$output_name" "$prefix"
        fi
        sync_runtime_monitor_overrides
        ;;
      restore)
        restore_output_state "$output_json" "$output_name" "$prefix"
        sync_runtime_monitor_overrides
        ;;
      status)
        monitor_status "$output_json" "$output_name" "$prefix"
        ;;
      discover)
        list_unknown_monitors
        ;;
      enable-discovered)
        enable_unknown_monitor "$output_name"
        ;;
      suggest)
        suggest_unknown_monitor_config "$output_name"
        ;;
      prompt-new)
        prompt_new_monitor_dialog "$output_name"
        ;;
      workspace-to)
        ensure_output_ready_for_workspace_move "$output_name"
        move_active_workspace_to_output "$output_name"
        ;;
      focused-workspaces-to)
        ensure_output_ready_for_workspace_move "$output_name"
        move_other_monitors_workspaces_to_target "$output_name"
        ;;
    esac
  '';
in
{
  inherit monitorStateScript;
  monitorOnScript = pkgs.writeShellScriptBin "wm-monitor-on" ''exec ${lib.getExe monitorStateScript} on "$@"'';
  monitorOffScript = pkgs.writeShellScriptBin "wm-monitor-off" ''exec ${lib.getExe monitorStateScript} off "$@"'';
  monitorToggleScript = pkgs.writeShellScriptBin "wm-monitor-toggle" ''exec ${lib.getExe monitorStateScript} toggle "$@"'';
  monitorRestoreScript = pkgs.writeShellScriptBin "wm-monitor-restore" ''exec ${lib.getExe monitorStateScript} restore "$@"'';
  monitorStatusScript = pkgs.writeShellScriptBin "wm-monitor-status" ''exec ${lib.getExe monitorStateScript} status "$@"'';
  monitorWorkspaceToScript = pkgs.writeShellScriptBin "wm-monitor-workspace-to" ''exec ${lib.getExe monitorStateScript} workspace-to "$@"'';
  monitorFocusedWorkspacesToScript = pkgs.writeShellScriptBin "wm-monitor-focused-workspaces-to" ''exec ${lib.getExe monitorStateScript} focused-workspaces-to "$@"'';
  monitorListScript = pkgs.writeShellScriptBin "wm-monitor-list" ''exec ${lib.getExe monitorStateScript} list "$@"'';
  monitorDiscoverScript = pkgs.writeShellScriptBin "wm-monitor-discover" ''exec ${lib.getExe monitorStateScript} discover "$@"'';
  monitorSuggestScript = pkgs.writeShellScriptBin "wm-monitor-suggest" ''exec ${lib.getExe monitorStateScript} suggest "$@"'';
  monitorNewDialogScript = pkgs.writeShellScriptBin "wm-monitor-new-dialog" ''exec ${lib.getExe monitorStateScript} prompt-new "$@"'';
  monitorDebugScript = pkgs.writeShellScriptBin "wm-monitor-debug" ''
    set -eu

    echo "== Hyprland monitors (all) =="
    ${hyprctlExec} -j monitors all || true
    echo
    echo "== Startup monitor defaults =="
    cat ${lib.escapeShellArg "${homeDirectory}/.config/hypr/conf.d/10-monitors.conf"} || true
    echo
    echo "== Runtime monitor overrides =="
    cat ${lib.escapeShellArg hyprlandRuntimeMonitorConfigPath} || true
  '';
}
