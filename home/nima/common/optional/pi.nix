{ config, lib, pkgs, ... }:

let
  # Keep settings.json writable: Pi's package manager updates this file when
  # installing/removing packages.  Home Manager links home.file entries into
  # the Nix store, which makes `pi install` fail with a read-only-file error.
  piSettings = pkgs.writeText "pi-settings.json" (builtins.toJSON {
    theme = "dark";
    defaultProvider = "openai-codex";
    defaultModel = "gpt-5.6-luna";
    defaultThinkingLevel = "high";
    outputPad = 0;
    quietStartup = true;
    tuiMode = "regular";
    warnings = {
      anthropicExtraUsage = false;
    };
  });
in
{
  # Install Pi wherever this module is imported.  Node/npm are also needed by
  # Pi's runtime package manager for `pi install npm:...`.
  home.packages = with pkgs; [
    unstable.pi-coding-agent
    nodejs
  ];

  # Merge Nix-owned defaults into a real file instead of linking settings.json
  # into the store.  The existing file wins for fields not declared above, so
  # Pi can own its `packages` list and `pi install` remains usable.
  #
  # Run before linkGeneration so the old Home Manager symlink is converted to a
  # regular file before Home Manager tries to remove it as an obsolete link.
  home.activation.piSettings = lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
    pi_dir="$HOME/.pi/agent"
    settings="$pi_dir/settings.json"
    mkdir -p "$pi_dir"

    tmp="$(mktemp "$pi_dir/settings.json.XXXXXX")"
    if [ -e "$settings" ]; then
      ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$settings" "${piSettings}" > "$tmp"
    else
      cp "${piSettings}" "$tmp"
    fi
    chmod 600 "$tmp"
    mv -f "$tmp" "$settings"
  '';

  # GPT-5.6 Luna supports the 1.05M-token long-context tier.
  home.file.".pi/agent/models.json".text = builtins.toJSON {
    providers."openai-codex".modelOverrides."gpt-5.6-luna" = {
      contextWindow = 1050000;
    };
  };
}
