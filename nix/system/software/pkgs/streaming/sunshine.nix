{
  lib,
  stdenv,
  fetchFromGitHub,
  autoPatchelfHook,
  autoAddDriverRunpath,
  makeWrapper,
  buildNpmPackage,
  nixosTests,
  cmake,
  avahi,
  libevdev,
  libpulseaudio,
  libxtst,
  libxrandr,
  libxi,
  libxfixes,
  libxdmcp,
  libx11,
  libxcb,
  openssl,
  libopus,
  boost,
  pkg-config,
  libdrm,
  wayland,
  wayland-scanner,
  libffi,
  libcap,
  libgbm,
  curl,
  pcre,
  pcre2,
  python3,
  libuuid,
  libselinux,
  libsepol,
  libthai,
  libdatrie,
  libxkbcommon,
  libepoxy,
  libva,
  libvdpau,
  libglvnd,
  numactl,
  amf-headers,
  svt-av1,
  vulkan-loader,
  libappindicator,
  libnotify,
  miniupnpc,
  nlohmann_json,
  config,
  coreutils,
  udevCheckHook,
  nixpkgsSrc,
  cudaSupport ? config.cudaSupport,
  cudaPackages ? { },
}:
let
  stdenv' = if cudaSupport then cudaPackages.backendStdenv else stdenv;
in
stdenv'.mkDerivation (finalAttrs: {
  pname = "sunshine";
  version = "2026.525.145348";

  src = fetchFromGitHub {
    owner = "LizardByte";
    repo = "Sunshine";
    tag = "v${finalAttrs.version}";
    hash = "sha256-nW3v/MSNN0GQIHmxJnPFrrvVOZCc31vaJzZI4DJE0AE=";
    fetchSubmodules = true;
  };

  ui = buildNpmPackage {
    inherit (finalAttrs) src version;
    pname = "sunshine-ui";
    npmDepsHash = lib.fakeHash;
    npmDepsFetcherVersion = 2;

    # Upstream does not ship the generated lockfile in releases.
    postPatch = ''
      cp ${nixpkgsSrc}/pkgs/by-name/su/sunshine/package-lock.json ./package-lock.json
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -a . "$out"/
      runHook postInstall
    '';
  };

  postPatch =
    ''
      substituteInPlace cmake/packaging/linux.cmake \
        --replace-fail 'find_package(Systemd)' "" \
        --replace-fail 'find_package(Udev)' ""

      substituteInPlace cmake/targets/common.cmake \
        --replace-fail 'find_program(NPM npm REQUIRED)' ""

      substituteInPlace packaging/linux/dev.lizardbyte.app.Sunshine.desktop \
        --subst-var-by PROJECT_NAME 'Sunshine' \
        --subst-var-by PROJECT_DESCRIPTION 'Self-hosted game stream host for Moonlight' \
        --subst-var-by SUNSHINE_DESKTOP_ICON 'sunshine' \
        --subst-var-by CMAKE_INSTALL_FULL_DATAROOTDIR "$out/share" \
        --replace-fail '/usr/bin/env systemctl start --u sunshine' 'sunshine'

      substituteInPlace packaging/linux/sunshine.service.in \
        --subst-var-by PROJECT_DESCRIPTION 'Self-hosted game stream host for Moonlight' \
        --subst-var-by SUNSHINE_EXECUTABLE_PATH $out/bin/sunshine \
        --replace-fail '/bin/sleep' '${lib.getExe' coreutils "sleep"}'

      substituteInPlace cmake/dependencies/Boost_Sunshine.cmake \
        --replace-fail $'        system\n' ""
      substituteInPlace cmake/dependencies/Boost_Sunshine.cmake \
        --replace-fail 'find_package(Boost CONFIG ''${BOOST_VERSION} EXACT COMPONENTS ''${BOOST_COMPONENTS})' \
                       $'set(Boost_NO_BOOST_CMAKE ON)\nfind_package(Boost 1.56 REQUIRED COMPONENTS ''${BOOST_COMPONENTS})'
      substituteInPlace third-party/Simple-Web-Server/CMakeLists.txt \
        --replace-fail 'find_package(Boost 1.53.0 COMPONENTS system REQUIRED)' \
                       'find_package(Boost 1.53.0 REQUIRED)' \
        --replace-fail 'target_link_libraries(simple-web-server INTERFACE Boost::boost Boost::system)' \
                       'target_link_libraries(simple-web-server INTERFACE Boost::boost)'
      substituteInPlace cmake/compile_definitions/linux.cmake \
        --replace-fail 'add_compile_definitions(SUNSHINE_PLATFORM="linux")' \
                       $'add_compile_definitions(SUNSHINE_PLATFORM="linux")\nadd_compile_definitions(BOOST_LOG_DYN_LINK BOOST_LOG_SETUP_DYN_LINK)'
      substituteInPlace cmake/compile_definitions/common.cmake \
        --replace-fail '        ''${Boost_LIBRARIES}' \
                       $'        ''${Boost_LIBRARIES}\n        ${boost.out}/lib/libboost_log_setup.so\n        ${boost.out}/lib/libboost_thread.so\n        ${boost.out}/lib/libboost_chrono.so\n        ${boost.out}/lib/libboost_atomic.so\n        ${boost.out}/lib/libboost_regex.so\n        ${boost.out}/lib/libboost_date_time.so'
      substituteInPlace cmake/compile_definitions/common.cmake \
        --replace-fail '        ${boost.out}/lib/libboost_log_setup.so' \
                       $'        ${boost.out}/lib/libboost_log.so\n        ${boost.out}/lib/libboost_log_setup.so'
      substituteInPlace cmake/targets/common.cmake \
        --replace-fail 'target_link_libraries(sunshine ''${SUNSHINE_EXTERNAL_LIBRARIES} ''${EXTRA_LIBS})' \
                       $'target_link_libraries(sunshine ''${SUNSHINE_EXTERNAL_LIBRARIES} ''${EXTRA_LIBS})\ntarget_link_libraries(sunshine ${boost.out}/lib/libboost_log.so ${boost.out}/lib/libboost_log_setup.so ${boost.out}/lib/libboost_thread.so ${boost.out}/lib/libboost_chrono.so ${boost.out}/lib/libboost_atomic.so ${boost.out}/lib/libboost_regex.so ${boost.out}/lib/libboost_date_time.so)'
    '';

  nativeBuildInputs =
    [
      cmake
      pkg-config
      python3
      makeWrapper
      wayland-scanner
      autoPatchelfHook
    ]
    ++ lib.optionals cudaSupport [
      autoAddDriverRunpath
      cudaPackages.cuda_nvcc
      (lib.getDev cudaPackages.cuda_cudart)
    ];

  buildInputs = [
    avahi
    libevdev
    libpulseaudio
    libx11
    libxcb
    libxfixes
    libxrandr
    libxtst
    libxi
    openssl
    libopus
    boost
    libdrm
    wayland
    libffi
    libevdev
    libcap
    libdrm
    curl
    pcre
    pcre2
    libuuid
    libselinux
    libsepol
    libthai
    libdatrie
    libxdmcp
    libxkbcommon
    libepoxy
    libva
    libvdpau
    numactl
    libgbm
    amf-headers
    svt-av1
    libappindicator
    libnotify
    miniupnpc
    nlohmann_json
  ] ++ lib.optionals cudaSupport [
    cudaPackages.cudatoolkit
    cudaPackages.cuda_cudart
  ];

  runtimeDependencies = [
    avahi
    libgbm
    libxrandr
    libxcb
    libglvnd
  ];

  cmakeFlags = [
    "-Wno-dev"
    (lib.cmakeBool "UDEV_FOUND" true)
    (lib.cmakeBool "SYSTEMD_FOUND" true)
    (lib.cmakeFeature "UDEV_RULES_INSTALL_DIR" "lib/udev/rules.d")
    (lib.cmakeFeature "SYSTEMD_USER_UNIT_INSTALL_DIR" "lib/systemd/user")
    (lib.cmakeFeature "SYSTEMD_MODULES_LOAD_DIR" "lib/modules-load.d")
    (lib.cmakeBool "BOOST_USE_STATIC" false)
    (lib.cmakeBool "BUILD_DOCS" false)
    (lib.cmakeFeature "SUNSHINE_PUBLISHER_NAME" "j0nix-os")
    (lib.cmakeFeature "SUNSHINE_PUBLISHER_WEBSITE" "https://github.com/TheJ0nix/j0nix-os")
    (lib.cmakeFeature "SUNSHINE_PUBLISHER_ISSUE_URL" "https://github.com/TheJ0nix/j0nix-os/issues")
  ] ++ lib.optionals (!cudaSupport) [
    (lib.cmakeBool "SUNSHINE_ENABLE_CUDA" false)
  ];

  env = {
    BUILD_VERSION = finalAttrs.version;
    BRANCH = "master";
    COMMIT = "";
  };

  preBuild = ''
    cp -r ${finalAttrs.ui}/build ../
  '';

  buildFlags = [ "sunshine" ];

  installPhase = ''
    runHook preInstall
    cmake --install .
    runHook postInstall
  '';

  postInstall = ''
    install -Dm644 ../packaging/linux/dev.lizardbyte.app.Sunshine.desktop \
      $out/share/applications/dev.lizardbyte.app.Sunshine.desktop
  '';

  postFixup = lib.optionalString cudaSupport ''
    wrapProgram $out/bin/sunshine \
      --set LD_LIBRARY_PATH ${lib.makeLibraryPath [ vulkan-loader ]}
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ udevCheckHook ];

  passthru = {
    tests.sunshine = nixosTests.sunshine;
  };

  meta = {
    description = "Game stream host for Moonlight";
    homepage = "https://github.com/LizardByte/Sunshine";
    license = lib.licenses.gpl3Only;
    mainProgram = "sunshine";
    maintainers = with lib.maintainers; [ devusb ];
    platforms = lib.platforms.linux;
  };
})
