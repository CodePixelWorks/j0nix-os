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
  version = "0.1.6";

  src = fetchFromGitHub {
    owner = "Nitrux";
    repo = "qmlgreet";
    rev = finalAttrs.version;
    hash = "sha256-B3H/ts58SpUG6172MIaD3g6MCYQd0e5CXcav0M2QkpU=";
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

  postPatch = ''
    # Remove hibernation variants from the greeter bottom bar.
    # They share the same icon (system-suspend-hibernate) and are
    # visually indistinguishable from each other in the UI.
    sed -i '/StyledButton { iconName: "system-suspend-hibernate";/d' qml/main.qml
  '';

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
