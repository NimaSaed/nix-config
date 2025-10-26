{ config, pkgs, ... }:

{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;

    config = {
      global = {
        # Automatically load .envrc files
        load_dotenv = true;
        # Hide direnv log output
        hide_env_diff = false;
      };
    };

    # Enable direnv integration with bash
    enableBashIntegration = true;
  };
}
