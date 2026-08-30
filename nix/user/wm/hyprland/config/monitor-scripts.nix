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
    notify_bin="${pkgs.libnotify}/bin/notify-send"
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
      echo "usage: wm-monitor <on|off|toggle|restore|status|workspace-to|focused-workspaces-to|list|discover|doctor|transaction-begin|transaction-end|enable-discovered|suggest|prompt-new|sync-live|sync-defaults|watch> [output-name]" >&2
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

    notify_display() {
      local summary="$1"
      local body="$2"

      [ -x "$notify_bin" ] || return 0
      "$notify_bin" -a "Display control" -r 43001 "$summary" "$body" >/dev/null 2>&1 || true
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

    transaction_dir() {
      printf '%s/transactions/%s' "$state_dir" "$(sanitize_name "$1")"
    }

    load_output_config() {
      local name="$1"
      "$jq_bin" -ce --arg name "$name" '.[] | select(.name == $name or (.id // "") == $name)' "$outputs_json"
    }

    load_output_binding() {
      local name="$1"
      "$jq_bin" -ce --arg name "$name" '.[] | select(.name == $name or (.id // "") == $name)' "$bindings_json"
    }

    load_initial_output_state() {
      local name="$1"
      "$jq_bin" -ce --arg name "$name" '.[] | select(.name == $name or (.id // "") == $name)' "$initial_states_json"
    }

    output_is_headless() {
      local name="$1"
      "$jq_bin" -e --arg name "$name" '.[] | select(.name == $name)' "$headless_outputs_json" >/dev/null 2>&1
    }

    ensure_headless_output() {
      local name="$1"
      output_is_headless "$name" || return 0
      if ! live_monitors_all_json | "$jq_bin" -e --arg name "$name" '.[] | select(.name == $name)' >/dev/null 2>&1; then
        "$hyprctl_bin" output create headless "$name" >/dev/null 2>&1 || true
        for _ in $(seq 1 50); do
          if live_monitors_all_json | "$jq_bin" -e --arg name "$name" '.[] | select(.name == $name)' >/dev/null 2>&1; then
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

    read_hyprctl_json() {
      local result rc

      for _ in $(seq 1 5); do
        set +e
        result="$("$hyprctl_bin" "$@" 2>&1)"
        rc=$?
        set -e

        if [ "$rc" -eq 0 ] && printf '%s' "$result" | "$jq_bin" -e . >/dev/null 2>&1; then
          printf '%s\n' "$result"
          return 0
        fi

        sleep 0.1
      done

      printf '%s\n' "$result" >&2
      return 1
    }

    require_output_name() {
      [ -n "$output_name" ] || usage
    }

    get_output_field() {
      local output_json="$1"
      local query="$2"
      printf '%s' "$output_json" | "$jq_bin" -r "$query"
    }

    output_state_key() {
      local output_json="$1"
      printf '%s' "$output_json" | "$jq_bin" -r '.id // .name // empty'
    }

    live_monitors_all_json() {
      read_hyprctl_json -j monitors all
    }

    live_monitors_json() {
      read_hyprctl_json -j monitors
    }

    resolve_output_name_from_live_json() {
      local output_json="$1"
      local live_json="$2"

      "$jq_bin" -n --argjson output "$output_json" --argjson live "$live_json" -r '
        def present($value): ($value // "") != "";
        def match_score($monitor; $match):
          (if present($match.description) and (($monitor.description // "") == $match.description) then 8 else 0 end)
          + (if present($match.serial) and (($monitor.serial // "") == $match.serial) then 4 else 0 end)
          + (if present($match.make) and (($monitor.make // "") == $match.make) then 2 else 0 end)
          + (if present($match.model) and (($monitor.model // "") == $match.model) then 1 else 0 end);

        ($output.name // "") as $declared
        | if (($live | any((.name // "") == $declared)) or (($output.match // {}) == {})) then
            $declared
          else
            ($output.match // {}) as $match
            | [
                $live[]
                | select((.name // "") != "")
                | { name: .name, score: match_score(.; $match) }
                | select(.score > 0)
              ]
              | sort_by(.score)
              | reverse
              | if length == 0 then
                  $declared
                elif length == 1 or .[0].score > .[1].score then
                  .[0].name
                else
                  $declared
                end
          end
      '
    }

    resolve_output_name() {
      local output_json="$1"
      local live_json

      live_json="$(live_monitors_all_json 2>/dev/null || true)"
      if [ -n "$live_json" ]; then
        resolve_output_name_from_live_json "$output_json" "$live_json"
      else
        printf '%s' "$output_json" | "$jq_bin" -r '.name // empty'
      fi
    }

    resolve_handoff_monitor_name() {
      local preferred_monitor="$1"
      local output_json

      [ -n "$preferred_monitor" ] || return 0
      output_json="$(load_output_config "$preferred_monitor" 2>/dev/null || true)"
      if [ -n "$output_json" ]; then
        resolve_output_name "$output_json"
      else
        printf '%s\n' "$preferred_monitor"
      fi
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
      live_monitors_json | "$jq_bin" -e --arg name "$name" '.[] | select(.name == $name and (.disabled // false) == false)' >/dev/null 2>&1
    }

    list_unknown_active_monitors() {
      live_monitors_all_json \
        | "$jq_bin" -c --slurpfile bindings "$bindings_json" '
            .[] as $monitor
            | select(($monitor.disabled // false) == false and ($monitor.name // "") != "")
            | select(((($bindings[0] // []) | map(.name)) | index($monitor.name)) == null)
            | $monitor
          '
    }

    get_live_monitor_json() {
      local name="$1"
      live_monitors_all_json | "$jq_bin" -ce --arg name "$name" '.[] | select(.name == $name and (.disabled // false) == false)'
    }

    monitor_spec_from_declared_output() {
      local output_json="$1"
      local name mode position scale

      name="$(resolve_output_name "$output_json")"
      mode="$(printf '%s' "$output_json" | "$jq_bin" -r '.mode // "preferred"')"
      position="$(printf '%s' "$output_json" | "$jq_bin" -r '.position // "auto"')"
      scale="$(printf '%s' "$output_json" | "$jq_bin" -r '(.scale // 1) | tostring')"
      [ -n "$name" ] || return 1
      printf '%s,%s,%s,%s\n' "$name" "$mode" "$position" "$scale"
    }

    monitor_spec_from_live_or_declared_output() {
      local output_json="$1"
      local name monitor_json mode position scale

      name="$(resolve_output_name "$output_json")"
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

      if live_monitors_all_json >/dev/null 2>&1; then
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
    $(live_monitors_json | "$jq_bin" -r '
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
      live_monitors_all_json | "$jq_bin" -ce --arg name "$name" '.[] | select(.name == $name)'
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
      live_monitors_all_json \
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

    run_monitor_doctor() {
      local live_json declared_json errors warnings missing_count optional_missing_count unknown_count handoff_count
      local duplicates_count stale_match_count known_live_count

      if ! live_json="$(read_hyprctl_json -j monitors all)"; then
        echo "ERROR: Hyprland monitor state is unavailable."
        echo "Hint: run this inside an active Hyprland session."
        return 1
      fi

      declared_json="$(
        "$jq_bin" -n \
          --slurpfile initial "$initial_states_json" \
          --slurpfile toggleable "$outputs_json" \
          --slurpfile bindings "$bindings_json" \
          --slurpfile headless "$headless_outputs_json" \
          --argjson live "$live_json" '
            def present($value): ($value // "") != "";
            def match_score($monitor; $match):
              (if present($match.description) and (($monitor.description // "") == $match.description) then 8 else 0 end)
              + (if present($match.serial) and (($monitor.serial // "") == $match.serial) then 4 else 0 end)
              + (if present($match.make) and (($monitor.make // "") == $match.make) then 2 else 0 end)
              + (if present($match.model) and (($monitor.model // "") == $match.model) then 1 else 0 end);
            def resolved_name($output):
              ($output.name // "") as $declared
              | if (($live | any((.name // "") == $declared)) or (($output.match // {}) == {})) then
                  $declared
                else
                  ($output.match // {}) as $match
                  | [
                      $live[]
                      | select((.name // "") != "")
                      | { name: .name, score: match_score(.; $match) }
                      | select(.score > 0)
                    ]
                    | sort_by(.score)
                    | reverse
                    | if length == 0 then
                        $declared
                      elif length == 1 or .[0].score > .[1].score then
                        .[0].name
                      else
                        $declared
                      end
                end;
            def source_entries($source; $items):
              ($items[0] // [])
              | map(select((.name // "") != "") | . + { source: $source });

            (
              source_entries("initial"; $initial)
              + source_entries("toggleable"; $toggleable)
              + source_entries("binding"; $bindings)
              + source_entries("headless"; $headless)
            ) as $entries
            | ($entries | map(.name) | unique) as $names
            | $names
            | map(
                . as $name
                | ($entries | map(select(.name == $name))) as $matches
                | {
                    name: $name,
                    resolvedName: resolved_name($matches[0]),
                    sources: ($matches | map(.source) | unique),
                    descriptions: (
                      $matches
                      | map(.description // "", .match.description // "")
                      | map(select(. != ""))
                      | unique
                    ),
                    bindIndices: ($matches | map(.bindIndex // null) | map(select(. != null)) | unique),
                    isHeadless: (($headless[0] // []) | any(.name == $name)),
                    enabledByDefault: (
                      $matches
                      | map(select(has("enabledByDefault")) | .enabledByDefault)
                      | if length == 0 then null else .[0] end
                    ),
                    handoffTargets: (
                      $matches
                      | map(.workspaceHandoff.targetMonitor? // "")
                      | map(select(. != ""))
                      | unique
                    )
                  }
              )
          '
      )"

      errors=0
      warnings=0

      echo "Monitor doctor"
      echo
      echo "Live outputs:"
      printf '%s' "$live_json" | "$jq_bin" -r '
        if length == 0 then
          "  - none"
        else
          .[]
          | "  - \(.name) [\(if (.disabled // false) then "disabled" else "active" end)] \(.description // ([.make // "", .model // ""] | map(select(. != "")) | join(" ")))"
        end
      '
      echo
      echo "Declared outputs:"
      printf '%s' "$declared_json" | "$jq_bin" -r '
        if length == 0 then
          "  - none"
        else
          .[]
          | "  - \(.name)\(if .resolvedName != .name then " -> \(.resolvedName)" else "" end) sources=\(.sources | join(","))\(if .isHeadless then " headless=true" else "" end)"
        end
      '
      echo

      missing_count="$(
        "$jq_bin" -n --argjson live "$live_json" --argjson declared "$declared_json" '
          [
            $declared[]
            | select(.isHeadless == false)
            | select(.enabledByDefault != false)
            | . as $declaredOutput
            | select(($live | any(.name == $declaredOutput.resolvedName)) | not)
          ] | length
        '
      )"
      if [ "$missing_count" -gt 0 ]; then
        errors=$((errors + missing_count))
        echo "ERROR: Enabled physical outputs are missing from Hyprland:"
        "$jq_bin" -n --argjson live "$live_json" --argjson declared "$declared_json" -r '
          $declared[]
          | select(.isHeadless == false)
          | select(.enabledByDefault != false)
          | . as $declaredOutput
          | select(($live | any(.name == $declaredOutput.resolvedName)) | not)
          | "  - \(.name) sources=\(.sources | join(","))"
        '
        echo "Hint: connector names can change across boots/GPU topology. Update the declaration or migrate this output to a stable match-based monitor id."
        echo
      fi

      optional_missing_count="$(
        "$jq_bin" -n --argjson live "$live_json" --argjson declared "$declared_json" '
          [
            $declared[]
            | select(.isHeadless == false)
            | select(.enabledByDefault == false)
            | . as $declaredOutput
            | select(($live | any(.name == $declaredOutput.resolvedName)) | not)
          ] | length
        '
      )"
      if [ "$optional_missing_count" -gt 0 ]; then
        echo "INFO: Disabled-by-default physical outputs are not currently present:"
        "$jq_bin" -n --argjson live "$live_json" --argjson declared "$declared_json" -r '
          $declared[]
          | select(.isHeadless == false)
          | select(.enabledByDefault == false)
          | . as $declaredOutput
          | select(($live | any(.name == $declaredOutput.resolvedName)) | not)
          | "  - \(.name) sources=\(.sources | join(","))"
        '
        echo
      fi

      stale_match_count="$(
        "$jq_bin" -n --argjson live "$live_json" --argjson declared "$declared_json" '
          [
            $declared[]
            | select(.isHeadless == false)
            | select(.enabledByDefault != false)
            | . as $declaredOutput
            | select(($live | any(.name == $declaredOutput.resolvedName)) | not)
            | . as $declaredOutput
            | $declaredOutput.descriptions[]
            | select(. != "")
            | . as $description
            | $live[]
            | select((.description // "") == $description and (.name // "") != $declaredOutput.name)
            | { declared: $declaredOutput.name, live: .name, description: $description }
          ] | length
        '
      )"
      if [ "$stale_match_count" -gt 0 ]; then
        warnings=$((warnings + stale_match_count))
        echo "WARN: Possible stale connector names with matching descriptions:"
        "$jq_bin" -n --argjson live "$live_json" --argjson declared "$declared_json" -r '
          $declared[]
          | select(.isHeadless == false)
          | select(.enabledByDefault != false)
          | . as $declaredOutput
          | select(($live | any(.name == $declaredOutput.resolvedName)) | not)
          | . as $declaredOutput
          | $declaredOutput.descriptions[]
          | select(. != "")
          | . as $description
          | $live[]
          | select((.description // "") == $description and (.name // "") != $declaredOutput.name)
          | "  - declared \($declaredOutput.name), live \(.name), description=\($description)"
        '
        echo
      fi

      unknown_count="$(
        "$jq_bin" -n --argjson live "$live_json" --argjson declared "$declared_json" '
          [
            $live[]
            | select((.disabled // false) == false)
            | select((.name // "") != "")
            | . as $liveOutput
            | select(($declared | any(.resolvedName == $liveOutput.name)) | not)
          ] | length
        '
      )"
      if [ "$unknown_count" -gt 0 ]; then
        warnings=$((warnings + unknown_count))
        echo "WARN: Active live outputs are not declared:"
        "$jq_bin" -n --argjson live "$live_json" --argjson declared "$declared_json" -r '
          $live[]
          | select((.disabled // false) == false)
          | select((.name // "") != "")
          | . as $liveOutput
          | select(($declared | any(.resolvedName == $liveOutput.name)) | not)
          | "  - \(.name) \(.description // ([.make // "", .model // ""] | map(select(. != "")) | join(" ")))"
        '
        echo "Hint: use wm-monitor-suggest <output-name> for a declarative snippet."
        echo
      fi

      handoff_count="$(
        "$jq_bin" -n --argjson declared "$declared_json" '
          [
            $declared[]
            | . as $source
            | $source.handoffTargets[]
            | . as $target
            | select(($declared | any(.name == $target)) | not)
            | { source: $source.name, target: $target }
          ] | length
        '
      )"
      if [ "$handoff_count" -gt 0 ]; then
        errors=$((errors + handoff_count))
        echo "ERROR: Workspace handoff targets are not declared:"
        "$jq_bin" -n --argjson declared "$declared_json" -r '
          $declared[]
          | . as $source
          | $source.handoffTargets[]
          | . as $target
          | select(($declared | any(.name == $target)) | not)
          | "  - \($source.name) -> \($target)"
        '
        echo
      fi

      duplicates_count="$(
        "$jq_bin" -n --argjson declared "$declared_json" '
          [
            $declared
            | map(.bindIndices[])
            | group_by(.)
            | map(select(length > 1))
            | .[]
          ] | length
        '
      )"
      if [ "$duplicates_count" -gt 0 ]; then
        errors=$((errors + duplicates_count))
        echo "ERROR: Duplicate monitor bind indices:"
        "$jq_bin" -n --argjson declared "$declared_json" -r '
          ($declared | map({ name, bindIndices }) | map(select((.bindIndices | length) > 0))) as $withBinds
          | ($withBinds | map(.bindIndices[]) | group_by(.) | map(select(length > 1)) | map(.[0]))[]
          | . as $idx
          | "  - \($idx): \($withBinds | map(select(.bindIndices | index($idx)) | .name) | join(", "))"
        '
        echo
      fi

      known_live_count="$(
        "$jq_bin" -n --argjson live "$live_json" --argjson declared "$declared_json" '
          [
            $declared[]
            | . as $declaredOutput
            | select(($live | any(.name == $declaredOutput.resolvedName)))
          ] | length
        '
      )"

      if [ "$errors" -eq 0 ] && [ "$warnings" -eq 0 ]; then
        echo "OK: monitor declarations match the current Hyprland output set."
      else
        echo "Summary: $errors error(s), $warnings warning(s), $known_live_count declared output(s) visible."
      fi

      [ "$errors" -eq 0 ]
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
      live_monitors_json \
        | "$jq_bin" -r --arg output "$name" '.[] | select(.name == $output) | .activeWorkspace.name // empty' >"$prefix.active-workspace"
      live_monitors_json \
        | "$jq_bin" -r '.[] | select(.focused == true) | .name // empty' >"$prefix.focused-monitor"
      save_output_runtime_spec "$output_json" "$prefix"
    }

    move_workspace() {
      local workspace_name="$1"
      local target_monitor="$2"
      [ -n "$workspace_name" ] || return 0
      [ -n "$target_monitor" ] || return 0
      "$hyprctl_bin" dispatch 'hl.dsp.exec_cmd("hyprctl dispatch moveworkspacetomonitor '"$workspace_name"' '"$target_monitor"'")' >/dev/null 2>&1 || true
    }

    get_monitor_active_workspace() {
      local name="$1"
      live_monitors_json | "$jq_bin" -r --arg name "$name" '.[] | select(.name == $name) | .activeWorkspace.name // empty'
    }

    get_focused_monitor() {
      live_monitors_json | "$jq_bin" -r '.[] | select(.focused == true) | .name // empty'
    }

    pick_handoff_monitor() {
      local source_monitor="$1"
      local preferred_monitor="$2"

      if [ -n "$preferred_monitor" ] && [ "$preferred_monitor" != "$source_monitor" ] && output_is_active "$preferred_monitor"; then
        printf '%s\n' "$preferred_monitor"
        return 0
      fi

      live_monitors_json         | "$jq_bin" -r --arg source "$source_monitor" '.[] | select((.disabled // false) == false and (.name // "") != "" and .name != $source) | .name'         | head -n 1
    }

    focus_monitor() {
      local name="$1"
      [ -n "$name" ] || return 0
      "$hyprctl_bin" dispatch 'hl.dsp.exec_cmd("hyprctl dispatch focusmonitor '"$name"'")' >/dev/null 2>&1 || true
    }

    activate_workspace_on_monitor() {
      local monitor_name="$1"
      local workspace_name="$2"

      [ -n "$monitor_name" ] || return 0
      [ -n "$workspace_name" ] || return 0

      focus_monitor "$monitor_name"
      "$hyprctl_bin" dispatch 'hl.dsp.focus({ workspace = "'"$workspace_name"'" })' >/dev/null 2>&1 || true
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

      live_monitors_json         | "$jq_bin" -r --arg target "$target_monitor" '.[] | select((.disabled // false) == false and (.name // "") != "" and .name != $target) | .name'         | while IFS= read -r source_monitor; do
            [ -n "$source_monitor" ] || continue
            move_monitor_workspaces_to_target "$source_monitor" "$target_monitor"
          done

      focus_monitor "$target_monitor"
    }

    ensure_output_ready_for_workspace_move() {
      local target_monitor="$1"
      local output_json prefix resolved_monitor

      [ -n "$target_monitor" ] || return 0
      output_json="$(load_output_config "$target_monitor" 2>/dev/null || true)"
      [ -n "$output_json" ] || return 0
      resolved_monitor="$(resolve_output_name "$output_json")"

      if ! output_is_active "$resolved_monitor"; then
        prefix="$(state_prefix "$(output_state_key "$output_json")")"
        enable_output "$output_json" "$resolved_monitor" "$prefix"
        sync_runtime_monitor_overrides_locked
      fi
    }

    disable_output() {
      local output_json="$1"
      local name="$2"
      local prefix="$3"
      local handoff_enabled target_monitor

      handoff_enabled="$(get_output_field "$output_json" 'if (.workspaceHandoff.enable // false) then "1" else "0" end')"
      target_monitor="$(get_output_field "$output_json" '.workspaceHandoff.targetMonitor // ""')"
      target_monitor="$(resolve_handoff_monitor_name "$target_monitor")"
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

       if output_is_headless "$name" && ! live_monitors_all_json | "$jq_bin" -e --arg name "$name" '.[] | select(.name == $name)' >/dev/null 2>&1; then
        "$hyprctl_bin" output create headless "$name" >/dev/null 2>&1 || true
        for _ in $(seq 1 50); do
          if live_monitors_all_json | "$jq_bin" -e --arg name "$name" '.[] | select(.name == $name)' >/dev/null 2>&1; then
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
            output_json="$(load_output_binding "$name" 2>/dev/null || true)"
            if [ -n "$output_json" ]; then
              name="$(resolve_output_name "$output_json")"
            fi
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
      local tmp_file monitor_line output name resolved_name unknown_monitor_json unknown_name unknown_spec

      mkdir -p "$(dirname "$runtime_config_path")"
      tmp_file="$(mktemp "$(dirname "$runtime_config_path")/.runtime-monitors.lua.XXXXXX")"
      {
        write_runtime_header
        "$jq_bin" -c '.[]' "$outputs_json" | while IFS= read -r output; do
          name="$(printf '%s' "$output" | "$jq_bin" -r '.name // empty')"
          [ -n "$name" ] || continue
          resolved_name="$(resolve_output_name "$output")"

          if output_is_active "$resolved_name"; then
            monitor_line="$(monitor_spec_from_live_or_declared_output "$output")"
          else
            monitor_line="''${resolved_name},disable"
          fi

          if output_is_active "$resolved_name"; then
            IFS=, read -r _name mode position scale <<EOF
    $monitor_line
    EOF
            render_monitor_enabled "$resolved_name" "$mode" "$position" "$scale"
          else
            render_monitor_disabled "$resolved_name"
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

    transaction_begin() {
      local transaction_name="$1"
      local target_key="$2"
      local target_mode="$3"
      local target_position="$4"
      local target_scale="$5"
      local staging_position="''${6:-$target_position}"
      local tx_dir target_json target_monitor active_workspace focused_monitor

      [ -n "$transaction_name" ] || usage
      [ -n "$target_key" ] || usage
      target_json="$(load_output_config "$target_key" 2>/dev/null || load_output_binding "$target_key" 2>/dev/null || true)"
      if [ -z "$target_json" ]; then
        echo "Unknown transaction target output: $target_key" >&2
        exit 1
      fi
      target_monitor="$(resolve_output_name "$target_json")"
      [ -n "$target_monitor" ] || exit 1
      tx_dir="$(transaction_dir "$transaction_name")"
      if [ -f "$tx_dir/active" ]; then
        transaction_end "$transaction_name" "$target_key"
      fi
      mkdir -p "$tx_dir"

      if output_is_headless "$target_monitor"; then
        ensure_headless_output "$target_monitor"
      fi

      live_monitors_all_json | "$jq_bin" -r --arg target "$target_monitor" '
        .[]
        | select((.name // "") != "" and .name != $target)
        | if (.disabled // false) then
            [.name, "disable", "", ""] | @tsv
          else
            [
              .name,
              (((.width // 0) | tostring) + "x" + ((.height // 0) | tostring) + "@" + ((.refreshRate // 60) | tostring)),
              (((.x // 0) | tostring) + "x" + ((.y // 0) | tostring)),
              ((.scale // 1) | tostring)
            ] | @tsv
          end
      ' >"$tx_dir/monitors.tsv.tmp"
      mv -f "$tx_dir/monitors.tsv.tmp" "$tx_dir/monitors.tsv"

      "$hyprctl_bin" -j workspaces \
        | "$jq_bin" -r '.[] | select((.name // "") != "" and (.monitor // "") != "") | [.name, .monitor] | @tsv' >"$tx_dir/workspaces.tsv.tmp"
      mv -f "$tx_dir/workspaces.tsv.tmp" "$tx_dir/workspaces.tsv"
      "$hyprctl_bin" -j activeworkspace | "$jq_bin" -r '.name // empty' >"$tx_dir/active-workspace"
      focused_monitor="$(get_focused_monitor || true)"
      printf '%s\n' "$focused_monitor" >"$tx_dir/focused-monitor"
      : >"$tx_dir/active"

      # Keep a headless target out of the physical desktop until every other
      # output has been disabled.  Enabling it at 0x0 first causes Hyprland's
      # overlap warnings because the primary output is commonly also at 0x0.
      apply_monitor_enabled "$target_monitor" "$target_mode" "$staging_position" "$target_scale"
      wait_for_output_state "$target_monitor" active

      active_workspace="$(cat "$tx_dir/active-workspace" 2>/dev/null || true)"
      if [ -f "$tx_dir/workspaces.tsv" ]; then
        while IFS=$'\t' read -r workspace_name monitor_name; do
          [ -n "$workspace_name" ] || continue
          [ "$workspace_name" = "$active_workspace" ] && continue
          [ "$monitor_name" = "$target_monitor" ] && continue
          move_workspace "$workspace_name" "$target_monitor"
        done <"$tx_dir/workspaces.tsv"
      fi
      if [ -n "$active_workspace" ]; then
        move_workspace "$active_workspace" "$target_monitor"
      fi

      if [ -f "$tx_dir/monitors.tsv" ]; then
        while IFS=$'\t' read -r monitor_name _mode _position _scale; do
          [ -n "$monitor_name" ] || continue
          apply_monitor_disabled "$monitor_name"
          wait_for_output_state "$monitor_name" inactive
        done <"$tx_dir/monitors.tsv"
      fi

      apply_monitor_enabled "$target_monitor" "$target_mode" "$target_position" "$target_scale"
      focus_monitor "$target_monitor"
      sync_runtime_monitor_overrides_locked
      notify_display "Sunshine display ready" "Streaming display enabled."
    }

    transaction_end() {
      local transaction_name="$1"
      local target_key="''${2:-}"
      local tx_dir target_json target_monitor active_workspace focused_monitor
      local monitor_name monitor_mode monitor_position monitor_scale

      [ -n "$transaction_name" ] || usage
      tx_dir="$(transaction_dir "$transaction_name")"
      [ -f "$tx_dir/active" ] || return 0

      if [ -f "$tx_dir/monitors.tsv" ]; then
        while IFS=$'\t' read -r monitor_name monitor_mode monitor_position monitor_scale; do
          [ -n "$monitor_name" ] || continue
          if [ "$monitor_mode" = "disable" ]; then
            apply_monitor_disabled "$monitor_name"
          else
            apply_monitor_enabled "$monitor_name" "$monitor_mode" "$monitor_position" "$monitor_scale"
            wait_for_output_state "$monitor_name" active
          fi
        done <"$tx_dir/monitors.tsv"
      fi

      sleep 0.2
      active_workspace="$(cat "$tx_dir/active-workspace" 2>/dev/null || true)"
      if [ -f "$tx_dir/workspaces.tsv" ]; then
        while IFS=$'\t' read -r workspace_name monitor_name; do
          [ -n "$workspace_name" ] || continue
          [ "$workspace_name" = "$active_workspace" ] && continue
          if output_is_active "$monitor_name"; then
            move_workspace "$workspace_name" "$monitor_name"
          else
            move_workspace "$workspace_name" "$(pick_handoff_monitor "$target_monitor" "")"
          fi
        done <"$tx_dir/workspaces.tsv"

        if [ -n "$active_workspace" ]; then
          while IFS=$'\t' read -r workspace_name monitor_name; do
            [ "$workspace_name" = "$active_workspace" ] || continue
            if output_is_active "$monitor_name"; then
              move_workspace "$workspace_name" "$monitor_name"
            else
              move_workspace "$workspace_name" "$(pick_handoff_monitor "$target_monitor" "")"
            fi
            break
          done <"$tx_dir/workspaces.tsv"
        fi
      fi

      if [ -n "$target_key" ]; then
        # Restore the target from initialOutputStates first.  Bindings describe
        # interactive controls and may omit enabledByDefault; using a binding
        # for a Sunshine headless output would therefore re-enable it on stop.
        target_json="$(load_initial_output_state "$target_key" 2>/dev/null || load_output_config "$target_key" 2>/dev/null || load_output_binding "$target_key" 2>/dev/null || true)"
        if [ -n "$target_json" ]; then
          target_monitor="$(resolve_output_name "$target_json")"
          if [ "$(get_output_field "$target_json" 'if (.enabledByDefault == false) then "0" else "1" end')" = "1" ]; then
            apply_monitor_enabled "$target_monitor" \
              "$(get_output_field "$target_json" '.mode // "preferred"')" \
              "$(get_output_field "$target_json" '.position // "auto"')" \
              "$(get_output_field "$target_json" '(.scale // 1) | tostring')"
          else
            apply_monitor_disabled "$target_monitor"
            wait_for_output_state "$target_monitor" inactive
          fi
        fi
      fi

      focused_monitor="$(cat "$tx_dir/focused-monitor" 2>/dev/null || true)"
      if [ -n "$focused_monitor" ]; then
        focus_monitor "$focused_monitor"
      fi
      rm -rf "$tx_dir"
      sync_runtime_monitor_overrides_locked
      notify_display "Sunshine display restored" "Desktop layout restored and virtual display disabled."
    }

    run_output_action() {
      local action="$1"
      local output_json="$2"
      local output_name="$3"
      local prefix="$4"
      local handoff_target

      case "$action" in
        on)
          enable_output "$output_json" "$output_name" "$prefix"
          sync_runtime_monitor_overrides_locked
          notify_display "Output enabled" "$output_name is ready."
          ;;
        off)
          disable_output "$output_json" "$output_name" "$prefix"
          sync_runtime_monitor_overrides_locked
          handoff_target="$(cat "$prefix.target-monitor" 2>/dev/null || true)"
          if [ -n "$handoff_target" ]; then
            notify_display "Output disabled" "$output_name disabled; workspaces moved to $handoff_target."
          else
            notify_display "Output disabled" "$output_name is disabled."
          fi
          ;;
        toggle)
          if output_is_active "$output_name"; then
            run_output_action off "$output_json" "$output_name" "$prefix"
          else
            run_output_action on "$output_json" "$output_name" "$prefix"
          fi
          ;;
        restore)
          restore_output_state "$output_json" "$output_name" "$prefix"
          sync_runtime_monitor_overrides_locked
          notify_display "Output restored" "$output_name and its saved workspaces were restored."
          ;;
      esac
    }

    run_workspace_action() {
      local action="$1"
      local target_key="$2"
      local target_name="$3"

      ensure_output_ready_for_workspace_move "$target_key"
      case "$action" in
        workspace-to)
          move_active_workspace_to_output "$target_name"
          notify_display "Workspace moved" "Active workspace moved to $target_name."
          ;;
        focused-workspaces-to)
          move_other_monitors_workspaces_to_target "$target_name"
          notify_display "Workspaces moved" "All normal workspaces moved to $target_name."
          ;;
      esac
      sync_runtime_monitor_overrides_locked
    }

    case "$command" in
      list)
        monitor_list
        exit 0
        ;;
      doctor)
        run_monitor_doctor
        exit $?
        ;;
      transaction-begin)
        with_runtime_lock transaction_begin "''${2:-}" "''${3:-}" "''${4:-preferred}" "''${5:-auto}" "''${6:-1}" "''${7:-auto}"
        exit 0
        ;;
      transaction-end)
        with_runtime_lock transaction_end "''${2:-}" "''${3:-}"
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
        output_key="$(output_state_key "$output_json")"
        resolved_output_name="$(resolve_output_name "$output_json")"
        prefix="$(state_prefix "$output_key")"
        ;;
      workspace-to|focused-workspaces-to)
        require_output_name
        if [ -s "$bindings_json" ]; then
          load_output_binding "$output_name" >/dev/null 2>&1 || {
            echo "Unknown output binding: $output_name" >&2
            exit 1
          }
        fi
        output_json="$(load_output_config "$output_name" 2>/dev/null || load_output_binding "$output_name" 2>/dev/null || true)"
        if [ -n "$output_json" ]; then
          resolved_output_name="$(resolve_output_name "$output_json")"
        else
          resolved_output_name="$output_name"
        fi
        ;;
      *)
        usage
        ;;
    esac

    case "$command" in
      on)
        with_runtime_lock run_output_action on "$output_json" "$resolved_output_name" "$prefix"
        ;;
      off)
        with_runtime_lock run_output_action off "$output_json" "$resolved_output_name" "$prefix"
        ;;
      toggle)
        with_runtime_lock run_output_action toggle "$output_json" "$resolved_output_name" "$prefix"
        ;;
      restore)
        with_runtime_lock run_output_action restore "$output_json" "$resolved_output_name" "$prefix"
        ;;
      status)
        monitor_status "$output_json" "$resolved_output_name" "$prefix"
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
        with_runtime_lock run_workspace_action workspace-to "$output_name" "$resolved_output_name"
        ;;
      focused-workspaces-to)
        with_runtime_lock run_workspace_action focused-workspaces-to "$output_name" "$resolved_output_name"
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
  monitorDoctorScript = pkgs.writeShellScriptBin "wm-monitor-doctor" ''exec ${lib.getExe monitorStateScript} doctor "$@"'';
  monitorSuggestScript = pkgs.writeShellScriptBin "wm-monitor-suggest" ''exec ${lib.getExe monitorStateScript} suggest "$@"'';
  monitorNewDialogScript = pkgs.writeShellScriptBin "wm-monitor-new-dialog" ''exec ${lib.getExe monitorStateScript} prompt-new "$@"'';
  monitorDebugScript = pkgs.writeShellScriptBin "wm-monitor-debug" ''
    set -eu

    echo "== Hyprland monitors (all) =="
    ${hyprctlExec} -j monitors all || true
    echo
    echo "== Startup monitor defaults =="
    cat ${lib.escapeShellArg "${homeDirectory}/.config/hypr/j0nix/monitors.lua"} || true
    echo
    echo "== Runtime monitor overrides =="
    cat ${lib.escapeShellArg hyprlandRuntimeMonitorConfigPath} || true
  '';
}
