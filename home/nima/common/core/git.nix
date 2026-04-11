{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    signing = {
      format = "ssh";
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILusNnhBC/pBjhZpx312e7TEzwS69SyN/0e/osA6Jez9";
      signByDefault = true;
    };
    settings = {
      user = {
        name = "Nima";
        email = "nima@nmsd.xyz";
      };
      init.defaultBranch = "main";
      pull.rebase = false;
      gpg.ssh.program = "${pkgs.openssh}/bin/ssh-keygen";
      alias = {
        st = "status";
        co = "checkout";
        br = "branch";
        ci = "commit";
        lg = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
      };
    };
  };
}
