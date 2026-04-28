setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_DATA_HOME="$HOME/.local/share"
  export FUSION360_ROOT="$XDG_DATA_HOME/autodesk-fusion"
  mkdir -p "$FUSION360_ROOT/wineprefixes/default"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/wine" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "$BATS_TEST_TMPDIR/bin/winetricks" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/wine" "$BATS_TEST_TMPDIR/bin/winetricks"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "doctor reports uninitialized install as informational" {
  run "$FUSION360_PACKAGE/bin/fusion360-doctor"
  [ "$status" -eq 0 ]
  [[ "$output" == *"installation has not been initialized yet"* ]]
}
