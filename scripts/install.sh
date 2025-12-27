#!/usr/bin/env bash
set -euo pipefail

# Usage: ./install.sh [remote-host] [1password-item] [flake-target]

REMOTE_HOST="${1:-root@chestnut.nmsd.xyz}"
OP_ITEM="${2:-Chestnut SOPS Age}"

# Extract hostname from REMOTE_HOST (e.g., root@chestnut.nmsd.xyz -> chestnut)
HOST_PART="${REMOTE_HOST#*@}"
FLAKE_TARGET="${3:-${HOST_PART%%.*}}"

# Create temporary directory for extra files
temp=$(mktemp -d)
cleanup() { rm -rf "$temp"; }
trap cleanup EXIT

# Create sops-nix directory structure
install -d -m755 "$temp/var/lib/sops-nix"

# Fetch age key from 1Password
echo "Fetching SOPS age key from 1Password..."
KEY_VALUE=$(op item get "$OP_ITEM" --fields notesPlain)

# Strip leading and trailing ``` from the note (first and last lines)
KEY_VALUE=$(echo "$KEY_VALUE" | sed '1d;$d')

if [[ -z "$KEY_VALUE" ]]; then
    echo "Error: Failed to retrieve key from 1Password or key is empty"
    exit 1
fi

# Write key with secure permissions
echo "$KEY_VALUE" > "$temp/var/lib/sops-nix/key.txt"
chmod 600 "$temp/var/lib/sops-nix/key.txt"

echo "Installing NixOS to $REMOTE_HOST with SOPS key..."
nix run github:numtide/nixos-anywhere -- \
    --build-on-remote \
    --extra-files "$temp" \
    --flake ".#$FLAKE_TARGET" \
    "$REMOTE_HOST"
