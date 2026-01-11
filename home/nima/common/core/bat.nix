{ config, pkgs, lib, ... }:

{
  # Disable bat cache build - workaround for memory allocation bug
  # See: https://discourse.nixos.org/t/bat-is-no-longer-working/38960
  home.activation.batCache = lib.mkForce "";

  programs.bat = {
    enable = true;

    config = {
      # Theme selection
      theme = "TwoDark";
      # Show line numbers
      style = "numbers,changes,header";
      # Use italic text
      italic-text = "always";
    };

    # Add custom themes or syntaxes if needed
    # themes = {};
    # syntaxes = {};
  };
}
