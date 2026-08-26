{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  procps,
  vulkan-loader,
  python3Packages,
}:
let
  pythonDependencies = with python3Packages; [
    colorama
    pyqtgraph
    pyside6
  ];
in
python3Packages.buildPythonApplication rec {
  pname = "penguin-burner";
  version = "0.7.9";
  format = "wheel";

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/77/56/7eb7125bad61688abd0ff586d2d2ab94e92f7dd81be8502722b88c04a410/penguin_burner-${version}-py3-none-manylinux_2_28_x86_64.whl";
    hash = "sha256-tNiMt5+R0U0pB3py2r4vb56aUigk8GXsILfwTYapOjw=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [
    stdenv.cc.cc.lib
    vulkan-loader
  ];
  dependencies = pythonDependencies;
  # nixpkgs' pyside6 output contains PySide6-Essentials but exposes the
  # distribution metadata as "pyside6", so the wheel-name check cannot match it.
  dontCheckRuntimeDeps = true;

  postInstall = ''
    desktopFile="$out/share/applications/io.github.jpietek.PenguinBurner.desktop"
    substituteInPlace "$desktopFile" \
      --replace-fail "GenericName=NVIDIA GPU Automatic Tuning Tool" "GenericName=NVIDIA GPU Tuning Tool" \
      --replace-fail "Name=NVIDIA GPU Automatic Tuning Tool" "Name=PenguinBurner"
  '';

  makeWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    "${lib.getBin procps}/bin"
    "--prefix"
    "PYTHONPATH"
    ":"
    "${builtins.placeholder "out"}/${python3Packages.python.sitePackages}:${python3Packages.makePythonPath pythonDependencies}"
    "--prefix"
    "LD_LIBRARY_PATH"
    ":"
    "/run/opengl-driver/lib"
  ];

  pythonImportsCheck = [
    "penguin_burner"
    "ui.main"
  ];

  meta = {
    description = "NVIDIA GPU automatic undervolting and tuning tool";
    homepage = "https://github.com/jpietek/PenguinBurner";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "penguin-burner";
  };
}
