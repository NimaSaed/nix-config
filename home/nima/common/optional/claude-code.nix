{ pkgs, ... }:

let
  # IS_DEMO=1 = skip the onboarding banner in every dir; nodejs = npx on claude's
  # PATH for npx-based MCP plugins (context7). Scoped to claude only.
  claude-code = pkgs.runCommand "claude-code-${pkgs.unstable.claude-code.version}"
    { nativeBuildInputs = [ pkgs.makeBinaryWrapper ]; }
    ''
      mkdir -p $out/bin
      makeWrapper ${pkgs.unstable.claude-code}/bin/claude $out/bin/claude \
        --set IS_DEMO 1 \
        --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.nodejs ]}
    '';
in
{
  home.packages = [ claude-code ];

  # Claude Code custom theme — Nebius brand palette.
  #
  # Based on the built-in "dark" (truecolor) theme rather than "dark-ansi":
  # ANSI base themes can't draw diff line backgrounds (they render added/removed
  # via foreground only), so we use the truecolor base to get diff fills and then
  # override the surface backgrounds to the terminal deep blue (#052B42) so
  # submitted messages blend in seamlessly — matching the alacritty Nebius theme.
  #
  # Activate in Claude Code with: /theme -> "Nebius".
  # Note: home-manager deploys this as a read-only store symlink, so live
  # editing via Ctrl+E in /theme won't work — change the colors here and rebuild.
  home.file.".claude/themes/nebius.json".text = builtins.toJSON {
    name = "Nebius";
    base = "dark";
    overrides = {
      # Surfaces — match the deep-blue terminal background
      background = "#052B42";
      userMessageBackground = "#052B42";
      userMessageBackgroundHover = "#0A3953";
      bashMessageBackgroundColor = "#052B42";
      memoryBackgroundColor = "#052B42";

      # Diff line highlights (dark green added / dark wine removed)
      diffAdded = "#123D24";
      diffAddedWord = "#1F6B3A";
      diffRemoved = "#481E26";
      diffRemovedWord = "#842A38";
      diffAddedDimmed = "#0C3119";
      diffRemovedDimmed = "#341922";
    };
  };
}
