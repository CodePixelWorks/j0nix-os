{ runCommand, bats, package }:

runCommand "autodesk-fusion-bats" { nativeBuildInputs = [ bats ]; } ''
  export FUSION360_PACKAGE=${package}
  bats ${./bats}
  touch "$out"
''
