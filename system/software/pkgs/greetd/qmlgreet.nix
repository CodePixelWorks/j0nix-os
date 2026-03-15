{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  meson,
  ninja,
  pkg-config,
  qt6,
  kdePackages,
  mauikit4,
  wayland,
  wayland-scanner,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "qmlgreet";
  version = "unstable-2026-03-08";

  src = fetchFromGitHub {
    owner = "Nitrux";
    repo = "qmlgreet";
    rev = "8a870dd17742e18d5571a690b9c7f2b8166dbbc5";
    hash = "sha256-lAXE8a8OhMz1SrobRb0ICTF77bQHEYv2ya+S4HC8gs0=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    cmake
    qt6.wrapQtAppsHook
    wayland-scanner
  ];

  buildInputs = [
    mauikit4
    qt6.qt5compat
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtimageformats
    qt6.qtwayland
    kdePackages.kirigami
    kdePackages.qqc2-desktop-style
    wayland
  ];

  qtWrapperArgs = [
    "--prefix QML2_IMPORT_PATH : ${mauikit4}/lib/qt-6/qml"
    "--prefix QML2_IMPORT_PATH : ${kdePackages.kirigami}/lib/qt-6/qml"
    "--prefix QML2_IMPORT_PATH : ${kdePackages.qqc2-desktop-style}/lib/qt-6/qml"
  ];

  postInstall = ''
    install -Dm644 "$src/qmlgreet.conf" "$out/share/qmlgreet/qmlgreet.conf"
    install -Dm644 "$src/QMLGreetDefault.colors" "$out/share/qmlgreet/QMLGreetDefault.colors"
  '';

  meta = {
    description = "QML-based greeter for greetd and Wayland compositors";
    homepage = "https://github.com/Nitrux/qmlgreet";
    license = lib.licenses.bsd3;
    maintainers = [ ];
    mainProgram = "qmlgreet";
    platforms = lib.platforms.linux;
  };
})
