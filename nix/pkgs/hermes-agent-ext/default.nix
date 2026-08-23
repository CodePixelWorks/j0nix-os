{
  stdenv,
  makeWrapper,
  hermesPackage,
  hermesExtraPython,
}:

stdenv.mkDerivation {
  pname = "hermes-agent-ext";
  inherit (hermesPackage) version;

  nativeBuildInputs = [ makeWrapper ];

  buildCommand = ''
    mkdir -p $out/bin $out/share $out/ui-tui

    if [[ -d ${hermesPackage}/share ]]; then
      cp -r ${hermesPackage}/share/* $out/share/
    fi
    if [[ -d ${hermesPackage}/ui-tui ]]; then
      cp -r ${hermesPackage}/ui-tui/* $out/ui-tui/
    fi

    extraSitePackages="${hermesExtraPython}/lib/python3.12/site-packages"

    for bin in hermes hermes-agent hermes-acp; do
      if [[ -e ${hermesPackage}/bin/$bin ]]; then
        makeWrapper ${hermesPackage}/bin/$bin $out/bin/$bin \
            --prefix PYTHONPATH : "$extraSitePackages" \
            --set-default FIRECRAWL_API_URL "http://127.0.0.1:3000" \
            --set-default FIRECRAWL_API_KEY "local" \
            --set-default QDRANT_URL "http://127.0.0.1:6333"
      fi
    done
  '';
}
