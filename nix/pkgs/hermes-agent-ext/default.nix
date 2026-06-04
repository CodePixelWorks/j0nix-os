{
  stdenv,
  makeWrapper,
  hermesPackage,
  firecrawlPy,
}:

stdenv.mkDerivation {
  pname = "hermes-agent-firecrawl";
  inherit (hermesPackage) version;

  nativeBuildInputs = [ makeWrapper ];

  buildCommand = ''
    mkdir -p $out/bin $out/share $out/ui-tui

    # Preserve bundled assets packaged by the original derivation.
    if [[ -d ${hermesPackage}/share ]]; then
      cp -r ${hermesPackage}/share/* $out/share/
    fi
    if [[ -d ${hermesPackage}/ui-tui ]]; then
      cp -r ${hermesPackage}/ui-tui/* $out/ui-tui/
    fi

    firecrawlSitePackages="${firecrawlPy}/lib/python3.12/site-packages"

    for bin in hermes hermes-agent hermes-acp; do
      if [[ -e ${hermesPackage}/bin/$bin ]]; then
        makeWrapper ${hermesPackage}/bin/$bin $out/bin/$bin \
            --prefix PYTHONPATH : "$firecrawlSitePackages"
      fi
    done
  '';
}
