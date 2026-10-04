{ config, lib, pkgs, ... }:

let
  cfg = config.programs.pi;
  jsonFormat = pkgs.formats.json { };

  # Nix-owned defaults.  Hosts can override or extend these via
  # `programs.pi.settings` (deep-merged, host wins).
  defaultSettings = {
    theme = "dark";
    defaultProvider = "openai-codex";
    defaultModel = "gpt-5.6-luna";
    defaultThinkingLevel = "high";
    outputPad = 0;
    quietStartup = true;
    tuiMode = "regular";
    # Nix owns the installed version; the post-update install ping is noise.
    enableInstallTelemetry = false;
    warnings = {
      anthropicExtraUsage = false;
    };
    # Pi auto-installs any listed package that is missing on startup, so a
    # fresh host picks these up on first launch.  Ad-hoc `pi install` entries
    # are preserved by the array union in the activation script below.
    packages = [
      "npm:pi-web-search"
    ];
  };

  # Keep settings.json writable: Pi's package manager updates this file when
  # installing/removing packages.  Home Manager links home.file entries into
  # the Nix store, which makes `pi install` fail with a read-only-file error.
  piSettings = jsonFormat.generate "pi-settings.json"
    (lib.recursiveUpdate defaultSettings cfg.settings);

  # Deep-merge Nix settings over the existing file (Nix wins for declared
  # keys), except `packages`, which is the union of both so runtime
  # `pi install` additions survive a `home-manager switch`.
  mergeFilter = ''
    . as [$cur, $nix]
    | ($cur * $nix)
    | .packages = (($cur.packages // []) + ($nix.packages // []) | unique)
  '';
in
{
  options.programs.pi.settings = lib.mkOption {
    type = jsonFormat.type;
    default = { };
    example = { defaultModel = "gpt-5.5"; defaultThinkingLevel = "medium"; };
    description = ''
      Per-host overrides for Pi's `~/.pi/agent/settings.json`.  Deep-merged
      over the module defaults; the result is merged into the real file at
      activation time so Pi can still write to it.
    '';
  };

  config = {
    # Install Pi wherever this module is imported.  npm (from nodejs) is needed
    # by Pi's runtime package manager for `pi install npm:...`; pin a major so
    # a nodejs bump doesn't silently break native deps of installed packages.
    home.packages = with pkgs; [
      unstable.pi-coding-agent
      nodejs_22
    ];

    # The Nix store install can't self-update, so the pi.dev latest-version
    # check only produces an un-actionable "new version available" banner.
    home.sessionVariables.PI_SKIP_VERSION_CHECK = "1";

    # Merge Nix-owned defaults into a real file instead of linking
    # settings.json into the store.  The existing file wins for fields not
    # declared above, so Pi can own e.g. `lastChangelogVersion`.
    #
    # Only rewrites the file when the merged result differs, and respects
    # `home-manager switch -n` (dry run).
    home.activation.piSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      pi_dir="${config.home.homeDirectory}/.pi/agent"
      settings="$pi_dir/settings.json"
      run mkdir -p "$pi_dir"

      if [ -e "$settings" ]; then
        merged="$(${lib.getExe pkgs.jq} -s ${lib.escapeShellArg mergeFilter} "$settings" "${piSettings}")"
      else
        merged="$(${lib.getExe pkgs.jq} . "${piSettings}")"
      fi

      if [ ! -e "$settings" ] || [ "$merged" != "$(cat "$settings")" ]; then
        verboseEcho "Updating $settings"
        if [[ -v DRY_RUN ]]; then
          echo "Would write $settings"
        else
          tmp="$(mktemp "$pi_dir/settings.json.XXXXXX")"
          printf '%s\n' "$merged" > "$tmp"
          chmod 600 "$tmp"
          mv -f "$tmp" "$settings"
        fi
      fi
    '';

    # GPT-5.6 Luna supports the 1.05M-token long-context tier.  Pi only reads
    # this file, so linking it from the store is fine.
    home.file.".pi/agent/models.json".source = jsonFormat.generate "pi-models.json" {
      providers."openai-codex".modelOverrides."gpt-5.6-luna" = {
        contextWindow = 1050000;
      };
    };
  };
}
