#!/usr/bin/env bash
set -euo pipefail

# Usage: ./install.sh <remote-host>

REMOTE_HOST="${1:?Usage: $0 <remote-host>}"

# Extract hostname from REMOTE_HOST (e.g., root@chestnut.nmsd.xyz -> chestnut)
HOST_PART="${REMOTE_HOST#*@}"
HOSTNAME="${HOST_PART%%.*}"

# Derive 1Password item name from hostname (e.g., chestnut -> Chestnut SOPS Age)
HOSTNAME_CAPITALIZED="$(echo "${HOSTNAME:0:1}" | tr '[:lower:]' '[:upper:]')${HOSTNAME:1}"
OP_ITEM="${HOSTNAME_CAPITALIZED} SOPS Age"

FLAKE_TARGET="$HOSTNAME"

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
nix run github:nix-community/nixos-anywhere/1.13.0 -- \
    --build-on remote \
    --extra-files "$temp" \
    --flake ".#$FLAKE_TARGET" \
    "$REMOTE_HOST"
