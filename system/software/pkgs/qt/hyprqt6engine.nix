{ lib
, stdenv
, fetchFromGitHub
, cmake
, ninja
, pkg-config
, hyprlang
, hyprutils
, libGL
, libxkbcommon
, kdePackages
, qt6
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "hyprqt6engine";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "hyprwm";
    repo = "hyprqt6engine";
    rev = "v${finalAttrs.version}";
    hash = "sha256-WSUMQmfVlpz31o2Tgfue0jnVRCeTrRi3Cy6s2/o8hzQ=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    qt6.wrapQtAppsHook
    qt6.qttools
  ];

  buildInputs = [
    hyprlang
    hyprutils
    libGL
    libxkbcommon
    kdePackages.kcolorscheme
    kdePackages.kconfig
    kdePackages.kiconthemes
    qt6.qt5compat
    qt6.qtbase
    qt6.qtsvg
    qt6.qtwayland
  ];

  postPatch = ''
    substituteInPlace common/config/ConfigManager.cpp \
      --replace-fail '/etc' '${placeholder "out"}/etc'
    substituteInPlace common/common.cpp \
      --replace-fail '/usr/share' '${placeholder "out"}/share'
  '';

  meta = with lib; {
    description = "Qt 6 platform theme and style provider for Hyprland";
    homepage = "https://github.com/hyprwm/hyprqt6engine";
    license = licenses.bsd3;
    platforms = platforms.linux;
    maintainers = [ ];
  };
})
