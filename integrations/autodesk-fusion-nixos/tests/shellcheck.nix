{ runCommand, shellcheck, package }:

runCommand "autodesk-fusion-shellcheck" { nativeBuildInputs = [ shellcheck ]; } ''
  shellcheck ${package}/bin/fusion360-install
  shellcheck ${package}/bin/fusion360-launch
  shellcheck ${package}/bin/fusion360-url-handler
  shellcheck ${package}/bin/fusion360-doctor
  shellcheck ${package}/bin/fusion360-fix-navbar
  touch "$out"
''
