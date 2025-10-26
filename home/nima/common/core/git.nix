{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    userName = "Nima"; # TODO: Update with your name
    userEmail = "nima@example.com"; # TODO: Update with your email

    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = false;
      core.editor = "vim";
    };

    # Useful git aliases
    aliases = {
      st = "status";
      co = "checkout";
      br = "branch";
      ci = "commit";
      lg =
        "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
    };
  };
}
