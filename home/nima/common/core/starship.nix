{ config, pkgs, ... }:

{
  programs.starship = {
    enable = true;

    settings = {
      # Add a new line before each prompt
      add_newline = true;

      # Character configuration
      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[➜](bold red)";
      };

      # Git branch configuration
      git_branch = {
        symbol = " ";
        style = "bold purple";
      };

      # Git status configuration
      git_status = {
        conflicted = "🏳";
        ahead = "⇡\${count}";
        behind = "⇣\${count}";
        diverged = "⇕⇡\${ahead_count}⇣\${behind_count}";
        untracked = "🤷";
        stashed = "📦";
        modified = "📝";
        staged = "[++($count)](green)";
        renamed = "👅";
        deleted = "🗑";
      };

      # Directory configuration
      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
        style = "bold cyan";
      };

      # Nix shell indicator
      nix_shell = {
        format = "via [$symbol$state( \($name\))]($style) ";
        symbol = "❄️ ";
      };
    };
  };
}
