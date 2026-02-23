{ config, pkgs, lib, settings, ... }:
{
  home.packages = with pkgs; [
    zsh
  ] ++ lib.optional ((((settings.programs or { }).fastfetch or { }).enable or true)) fastfetch;

  programs = {
    starship = {
      enable = true;
      enableZshIntegration = true;
    };

    zsh = {
      enable = true;
      dotDir = "${config.xdg.configHome}/zsh";
      autosuggestion.enable = true;
      historySubstringSearch.enable = true;
      enableCompletion = true;

      syntaxHighlighting = {
        enable = true;
        highlighters = [
          "main"
          "brackets"
          "pattern"
          "regexp"
          "root"
          "line"
        ];
      };

      history = {
        ignoreDups = true;
        save = 10000;
        size = 10000;
      };

      oh-my-zsh.enable = true;

      initContent = ''
        bindkey "\eh" backward-word
        bindkey "\ej" down-line-or-history
        bindkey "\ek" up-line-or-history
        bindkey "\el" forward-word

        if [ -f "$HOME/.zshrc-personal" ]; then
          source "$HOME/.zshrc-personal"
        fi

        if [[ -z "$FASTFETCH_LAUNCHED" ]] && command -v fastfetch >/dev/null 2>&1; then
          export FASTFETCH_LAUNCHED=1
          fastfetch
        fi
      '';

      shellAliases = {
        v = "nvim";
        sv = "sudo nvim";
        c = "clear";
        cat = "bat";
        man = "batman";
        ls = "eza --icons=auto";
        ll = "eza -lha --icons=auto";
        ".." = "cd ..";
        "..." = "cd ../..";
        ncg = "nix-collect-garbage --delete-old && sudo nix-collect-garbage -d";
        rebuild = "sudo nixos-rebuild switch --flake ${settings.dotfilesDir}#${settings.hostname}";
      };
    };
  };

  home.file.".zshrc-personal".text = ''
    export PATH="$HOME/.local/bin:$PATH"
    export EDITOR="${settings.preferredEditor or "nvim"}"
    export BROWSER="${settings.preferredBrowser or "zen"}"
  '';
}
