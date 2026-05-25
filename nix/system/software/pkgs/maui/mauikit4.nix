{
  lib,
  stdenv,
  fetchFromGitLab,
  cmake,
  ninja,
  pkg-config,
  qt6,
  kdePackages,
  mauiman4,
  libxcb,
  xcbutilwm,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "mauikit";
  version = "4.0.2";

  src = fetchFromGitLab {
    domain = "invent.kde.org";
    owner = "maui";
    repo = "mauikit";
    rev = "v${finalAttrs.version}";
    hash = "sha256-OHP7aDNaf/iJ/6lfY5jFlEKgdow0sD0vMCyjLhT6Y1A=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    kdePackages.extra-cmake-modules
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    kdePackages.kcoreaddons
    kdePackages.ki18n
    kdePackages.knotifications
    kdePackages.kwindowsystem
    mauiman4
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtmultimedia
    qt6.qtsvg
    libxcb
    xcbutilwm
  ];

  propagatedBuildInputs = [
    mauiman4
  ];

  cmakeFlags = [
    "-DBUILD_TESTING=OFF"
    "-DBUILD_DEMO=OFF"
    "-DBUNDLE_LUV_ICONS=OFF"
  ];

  meta = {
    description = "MauiKit UI framework and QML controls";
    homepage = "https://invent.kde.org/maui/mauikit";
    license = lib.licenses.gpl3Plus;
    maintainers = [ ];
    platforms = lib.platforms.linux;
  };
})
