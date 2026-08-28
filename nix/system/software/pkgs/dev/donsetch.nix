{
  autoPatchelfHook,
  chromium,
  fetchurl,
  gcc,
  lib,
  makeWrapper,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "donsetch";
  version = "3.3.0";

  src = fetchurl {
    url = "https://github.com/dondai44423/donsetch/releases/download/v${finalAttrs.version}/donsetch-linux-x64.tar.gz";
    hash = "sha256-aZ0QRTtKjUrguoB/t+vbKO9kUMGog2wE0SnroW5+d38=";
  };

  sourceRoot = ".";
  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [ gcc.cc.lib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 donsetch $out/bin/donsetch
    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/donsetch \
      --set-default DONGHOST_CHROME ${lib.getExe chromium}
  '';

  meta = {
    description = "Local web search, fetch, and crawl server for AI agents";
    homepage = "https://github.com/dondai44423/donsetch";
    license = lib.licenses.agpl3Only;
    mainProgram = "donsetch";
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
})
