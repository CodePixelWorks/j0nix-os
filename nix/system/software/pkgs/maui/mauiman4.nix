{
  lib,
  stdenv,
  fetchFromGitLab,
  cmake,
  ninja,
  pkg-config,
  qt6,
  kdePackages,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "mauiman";
  version = "4.0.2";

  src = fetchFromGitLab {
    domain = "invent.kde.org";
    owner = "maui";
    repo = "mauiman";
    rev = "v${finalAttrs.version}";
    hash = "sha256-1ia06/haUeb27p11EwDdJ/am5VDUzb9Up0/PgDplluQ=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    kdePackages.extra-cmake-modules
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    qt6.qtbase
  ];

  cmakeFlags = [
    "-DBUILD_TESTING=OFF"
  ];

  meta = {
    description = "Server and API for syncing global system setting preferences";
    homepage = "https://invent.kde.org/maui/mauiman";
    license = lib.licenses.gpl3Plus;
    maintainers = [ ];
    platforms = lib.platforms.linux;
  };
})
