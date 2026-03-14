{ lib
, stdenv
, fetchFromGitHub
, cmake
, extra-cmake-modules
, wrapQtAppsHook
, qtbase
, qtdeclarative
, kcmutils
, kcoreaddons
, kcolorscheme
, kconfig
, kguiaddons
, ki18n
, kiconthemes
, kwindowsystem
, kdecoration
, kirigami
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "darkly-qt6";
  version = "0.5.35";

  src = fetchFromGitHub {
    owner = "Bali10050";
    repo = "Darkly";
    rev = "v${finalAttrs.version}";
    hash = "sha256-PEy2ae8mEA39DOvpr9yBWDxta0wDm2acHQtjQ4yMiz0=";
  };

  nativeBuildInputs = [
    cmake
    extra-cmake-modules
    wrapQtAppsHook
  ];

  buildInputs = [
    qtbase
    qtdeclarative
    kcmutils
    kcoreaddons
    kcolorscheme
    kconfig
    kguiaddons
    ki18n
    kiconthemes
    kwindowsystem
    kdecoration
    kirigami
  ];

  cmakeFlags = [
    "-DBUILD_QT5=OFF"
    "-DBUILD_QT6=ON"
    "-DWITH_DECORATIONS=OFF"
  ];

  meta = with lib; {
    description = "Modern dark Qt 6 widget style forked from Breeze";
    homepage = "https://github.com/Bali10050/Darkly";
    license = licenses.gpl2Plus;
    mainProgram = "darkly-settings6";
    platforms = platforms.linux;
    maintainers = [ ];
  };
})
