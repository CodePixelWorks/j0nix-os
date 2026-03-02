{ pkgs, ... }:
{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    withNodeJs = true;
    withPython3 = true;

    initLua = ''
      vim.g.mapleader = " "
      vim.opt.number = true
      vim.opt.relativenumber = true
      vim.opt.expandtab = true
      vim.opt.shiftwidth = 2
      vim.opt.tabstop = 2
      vim.opt.smartindent = true
      vim.opt.termguicolors = true
      vim.opt.clipboard = "unnamedplus"
      vim.opt.updatetime = 250
    '';
  };

  j0nix.user.software.packages = with pkgs; [
    ripgrep
    fd
    tree-sitter
    gcc
    gnumake
    git
    lazygit
    nodejs
    python3
    lua-language-server
    nil
    nixd
    pyright
    clang-tools
    rust-analyzer
    gopls
    stylua
    nixfmt
  ];
}
