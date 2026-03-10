{ bottles, lib, makeWrapper, steam-run }:

bottles.overrideAttrs (old: {
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ makeWrapper ];

  postFixup =
    (old.postFixup or "")
    + ''
      runner_file="$(find "$out" -type f -name runner.py | head -n 1 || true)"
      if [ -n "$runner_file" ]; then
        if grep -Fq ' {runner}' "$runner_file"; then
          substituteInPlace "$runner_file" \
            --replace-fail ' {runner}' ' ${steam-run}/bin/steam-run {runner}'
        fi
        if grep -Fq ' {dxvk_setup}' "$runner_file"; then
          substituteInPlace "$runner_file" \
            --replace-fail ' {dxvk_setup}' ' ${steam-run}/bin/steam-run {dxvk_setup}'
        fi
      fi

      for program in "$out/bin/bottles" "$out/bin/bottles-cli"; do
        if [ -x "$program" ]; then
          wrapProgram "$program" \
            --prefix PATH : ${lib.makeBinPath [ steam-run ]}
        fi
      done
    '';

  passthru = (old.passthru or { }) // {
    j0nix = (old.passthru.j0nix or { }) // {
      steamRunWrapped = true;
    };
  };
})
