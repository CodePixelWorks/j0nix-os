{
  lib,
  fetchurl,
  buildPythonPackage,
  setuptools,
  requests,
  pydantic,
  python-dotenv,
  typing-extensions,
  websockets,
  nest-asyncio,
  aiohttp,
}:

buildPythonPackage rec {
  pname = "firecrawl-py";
  version = "2.16.5";

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/source/f/firecrawl-py/firecrawl_py-${version}.tar.gz";
    sha256 = "10scr8f9p2ajg5sysgd3xpxjprh4lr8ba9v818a2d92rlfxqclbz";
  };

  pyproject = true;
  build-system = [ setuptools ];

  propagatedBuildInputs = [
    requests
    pydantic
    python-dotenv
    typing-extensions
    websockets
    nest-asyncio
    aiohttp
  ];

  pythonImportsCheck = [ "firecrawl" ];

  meta = with lib; {
    description = "Python SDK for Firecrawl API";
    homepage = "https://github.com/mendableai/firecrawl";
    license = licenses.agpl3Only;
    maintainers = [ ];
  };
}
