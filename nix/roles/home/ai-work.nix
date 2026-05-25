{ pkgs, ... }:
{
  j0nix.user.software.packages = with pkgs; [
    aichat
    ollama
    llama-cpp
    uv
    python3Packages.jupyterlab
  ];
}
