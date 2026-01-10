{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Nima";
        email = "nima@nmsd.xyz";
      };
      init.defaultBranch = "main";
      pull.rebase = false;
      core.editor = "vim";
      alias = {
        st = "status";
        co = "checkout";
        br = "branch";
        ci = "commit";
        lg =
          "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
      };
    };
  };
}
