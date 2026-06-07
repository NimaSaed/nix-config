{
  config,
  pkgs,
  lib,
  ...
}:

{
  # ===========================================================================
  # Bitwarden + SOPS integration (shared)
  # ===========================================================================
  # Provides the `bw-sops-key` helper used as SOPS_AGE_KEY_CMD (wired up in
  # common/core/bash.nix when `bw` is on PATH). On Linux we also install the
  # Bitwarden CLI from nixpkgs; on macOS `bw` comes from Homebrew
  # (see hosts/mac/default.nix), so we don't add it twice.

  home.packages =
    [
      # Bitwarden SOPS key helper — used as SOPS_AGE_KEY_CMD
      (pkgs.writeShellScriptBin "bw-sops-key" ''
        set -euo pipefail
        status=$(bw status | ${pkgs.jq}/bin/jq -r .status)
        if [ "$status" = "unauthenticated" ]; then
          echo "bw-sops-key: Bitwarden is not logged in. Run: bw login" >&2
          exit 1
        fi
        if [ -z "''${BW_SESSION:-}" ]; then
          if [ "$status" = "locked" ]; then
            echo "Bitwarden vault is locked. Enter master password to unlock:" >/dev/tty
            BW_SESSION=$(bw unlock --raw </dev/tty)
          fi
        fi
        bw get item 729c67c1-e6a8-4b7f-8ca5-fa2a9439d698 --session "$BW_SESSION" | ${pkgs.jq}/bin/jq -r .login.password
      '')
    ]
    ++ lib.optionals pkgs.stdenv.isLinux [
      pkgs.bitwarden-cli # `bw` (macOS uses the Homebrew package instead)
    ];
}
