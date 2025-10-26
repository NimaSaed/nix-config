{ config, pkgs, ... }:

{
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
