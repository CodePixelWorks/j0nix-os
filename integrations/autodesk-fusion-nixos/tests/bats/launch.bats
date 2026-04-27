setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_DATA_HOME="$HOME/.local/share"
  export FUSION360_ROOT="$XDG_DATA_HOME/autodesk-fusion"
  mkdir -p "$FUSION360_ROOT/logs"
  mkdir -p "$FUSION360_ROOT/wineprefixes/default/drive_c/Program Files/Autodesk/Fusion"
  touch "$FUSION360_ROOT/wineprefixes/default/drive_c/Program Files/Autodesk/Fusion/Fusion360.exe"
  {
    echo "dxvk"
    echo "$FUSION360_ROOT"
    echo "$FUSION360_ROOT/wineprefixes/default"
    echo "Wine"
  } > "$FUSION360_ROOT/logs/wineprefixes.log"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export FUSION360_TEST_OUTPUT="$BATS_TEST_TMPDIR/launch-args"
  {
    printf '#!%s\n' "$(command -v bash)"
    printf '%s\n' 'printf "%s\n" "$*" > "$FUSION360_TEST_OUTPUT"'
  } > "$BATS_TEST_TMPDIR/bin/wine"
  chmod +x "$BATS_TEST_TMPDIR/bin/wine"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export FUSION360_WINE_BIN="$BATS_TEST_TMPDIR/bin/wine"
}

@test "launcher finds Fusion360.exe in the active prefix" {
  run "$FUSION360_PACKAGE/bin/fusion360-launch"
  [ "$status" -eq 0 ] || printf '%s\n' "$output"
  [ "$status" -eq 0 ]
  grep -q "Fusion360.exe" "$BATS_TEST_TMPDIR/launch-args"
}
