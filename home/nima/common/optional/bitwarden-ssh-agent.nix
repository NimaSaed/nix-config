{ config, ... }:

let
  agentSocket = "${config.home.homeDirectory}/.bitwarden-ssh-agent.sock";
in
{
  # ===========================================================================
  # Bitwarden SSH agent (shared)
  # ===========================================================================
  # Route SSH — including git commit signing — through the Bitwarden desktop SSH
  # agent. The native Bitwarden build (Homebrew on macOS, nixpkgs on Linux)
  # exposes the socket at ~/.bitwarden-ssh-agent.sock on every platform, so this
  # module is host-agnostic. (Snap/Flatpak builds use different socket paths and
  # are not used here.)
  home.sessionVariables.SSH_AUTH_SOCK = agentSocket;

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks."*".extraOptions = {
      IdentityAgent = agentSocket;
    };
  };
}
