{ pkgs, lib, settings, ... }:
{
  j0nix.user.software.packages = with pkgs; [
    fish
  ] ++ lib.optional ((((settings.programs or { }).fastfetch or { }).enable or true)) fastfetch;

  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      set fish_greeting

      if not set -q FASTFETCH_LAUNCHED; and command -q fastfetch
        set -gx FASTFETCH_LAUNCHED 1
        fastfetch
      end

      if test -f $HOME/.fishrc-personal
        source $HOME/.fishrc-personal
      end
    '';

    shellInit = ''
      fish_add_path $HOME/.local/bin
      fish_add_path $HOME/.pub-cache/bin
    '';

    functions = {
      fish_user_key_bindings = ''
        bind \eh backward-word
        bind \ej down-line-or-history
        bind \ek up-line-or-history
        bind \el forward-word
      '';
    };

    shellAliases = {
      v = "nvim";
      sv = "sudo nvim";
      c = "clear";
      cat = "bat";
      ls = "eza --icons=auto";
      ll = "eza -lha --icons=auto";
      ".." = "cd ..";
      "..." = "cd ../..";
      mkdir = "mkdir -p";
      ncg = "nix-collect-garbage --delete-old && sudo nix-collect-garbage -d";
      rebuild = "sudo nixos-rebuild switch --flake ${settings.dotfilesDir}#${settings.hostname}";
    };

    plugins = [
      {
        name = "fzf-fish";
        src = pkgs.fishPlugins.fzf-fish.src;
      }
      {
        name = "autopair";
        src = pkgs.fishPlugins.autopair.src;
      }
      {
        name = "done";
        src = pkgs.fishPlugins.done.src;
      }
      {
        name = "sponge";
        src = pkgs.fishPlugins.sponge.src;
      }
    ];
  };

  home.file.".fishrc-personal".text = ''
    set -gx EDITOR "${settings.preferredEditor or "nvim"}"
    set -gx BROWSER "${settings.preferredBrowser or "zen"}"
  '';
}
