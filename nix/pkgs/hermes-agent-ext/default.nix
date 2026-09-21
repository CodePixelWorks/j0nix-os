{
  stdenv,
  makeWrapper,
  hermesPackage,
  hermesExtraPython,
}:

# Wraps the curated hermes package (NixOS/hermes) with workstation-only
# Python extras. History: this was the firecrawl era (FIRECRAWL_API_URL/
# KEY env + firecrawl-py + qdrant-client on PYTHONPATH). Since the
# DonSeTch web-plugin switch and the mem0/qdrant memory migration, the
# only extra is the `ollama` pip client (mem0 OSS llm/embedder).
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
            --prefix PYTHONPATH : "$extraSitePackages"
      fi
    done
  '';
}
