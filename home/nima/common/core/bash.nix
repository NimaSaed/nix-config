{ config, pkgs, ... }:

{
  programs.bash = {
    enable = true;

    shellAliases = {
      ll = "ls -la";
      la = "ls -A";
      l = "ls -CF";
      ".." = "cd ..";
      "..." = "cd ../..";
      grep = "grep --color=auto";
    };

    bashrcExtra = ''
      # Custom bash configuration
      export EDITOR="vim"

      # Better history
      export HISTSIZE=10000
      export HISTFILESIZE=10000
      export HISTCONTROL=ignoredups:erasedups

      # Append to history, don't overwrite
      shopt -s histappend
    '';
  };
}
