#!/usr/bin/env bash
set -euo pipefail

# Usage: ./setup-sops-key.sh <remote-host> <1password-item>
# Example: ./setup-sops-key.sh user@server.example.com "sops-age-key"

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <remote-host> <1password-item>"
    echo "Example: $0 root@myserver 'SOPS Age Key'"
    exit 1
fi

REMOTE_HOST="$1"
OP_ITEM="$2"
REMOTE_DIR="/var/lib/sops-nix"
REMOTE_FILE="${REMOTE_DIR}/key.txt"

echo "Fetching secure note from 1Password..."
KEY_VALUE=$(op item get "$OP_ITEM" --fields notesPlain)

# Strip leading and trailing ``` from the note
KEY_VALUE=$(echo "$KEY_VALUE" | sed '1d;$d')

if [[ -z "$KEY_VALUE" ]]; then
    echo "Error: Failed to retrieve secure note or note is empty"
    exit 1
fi

echo "Creating ${REMOTE_DIR} on ${REMOTE_HOST}..."
ssh "$REMOTE_HOST" "sudo mkdir -p ${REMOTE_DIR}"

echo "Writing key.txt and setting permissions..."
echo "$KEY_VALUE" | ssh "$REMOTE_HOST" "sudo tee ${REMOTE_FILE} > /dev/null && sudo chmod 600 ${REMOTE_FILE}"

echo "Done! Key installed at ${REMOTE_HOST}:${REMOTE_FILE}"
