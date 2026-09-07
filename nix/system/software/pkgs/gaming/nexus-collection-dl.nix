{
  lib,
  fetchFromGitHub,
  python3Packages,
}:
python3Packages.buildPythonApplication rec {
  pname = "nexus-collection-dl";
  version = "0.2.0-unstable-2026-04-06";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "scottmccarrison";
    repo = "nexus-collection-dl";
    rev = "64fd56532a9f0e4c000d5815ee481b3d6ffd6827";
    hash = "sha256-t/3UoVhrdzovwOMtPh8Bn8asyKunh3yS7QtNCwO4wLU=";
  };

  build-system = [ python3Packages.setuptools ];

  dependencies = with python3Packages; [
    click
    flask
    packaging
    py7zr
    rarfile
    requests
    rich
  ];

  pythonImportsCheck = [ "nexus_collection_dl" ];

  meta = {
    description = "Nexus Mods collection downloader and deployment manager";
    homepage = "https://github.com/scottmccarrison/nexus-collection-dl";
    license = lib.licenses.mit;
    mainProgram = "nexus-dl";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
