#!/usr/bin/env bash
set -euo pipefail

# Usage: ./setup-sops-key.sh <remote-host> <bw-item-name>
# Example: ./setup-sops-key.sh user@server.example.com "Chestnut SOPS Age"

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <remote-host> <bw-item-name>"
    echo "Example: $0 root@myserver 'Chestnut SOPS Age'"
    exit 1
fi

REMOTE_HOST="$1"
BW_ITEM="$2"
REMOTE_DIR="/var/lib/sops-nix"
REMOTE_FILE="${REMOTE_DIR}/key.txt"

echo "Fetching SOPS age key from Bitwarden..."
if [[ -z "${BW_SESSION:-}" ]]; then
    BW_SESSION=$(bw unlock --raw)
fi
KEY_VALUE=$(bw list items --search "$BW_ITEM" --session "$BW_SESSION" --pretty | jq -r '.[0].notes')

# Strip leading and trailing ``` from the note if present
KEY_VALUE=$(echo "$KEY_VALUE" | sed '1d;$d')

if [[ -z "$KEY_VALUE" ]]; then
    echo "Error: Failed to retrieve key from Bitwarden or key is empty"
    exit 1
fi

echo "Creating ${REMOTE_DIR} on ${REMOTE_HOST}..."
ssh "$REMOTE_HOST" "sudo mkdir -p ${REMOTE_DIR}"

echo "Writing key.txt and setting permissions..."
echo "$KEY_VALUE" | ssh "$REMOTE_HOST" "sudo tee ${REMOTE_FILE} > /dev/null && sudo chmod 600 ${REMOTE_FILE}"

echo "Done! Key installed at ${REMOTE_HOST}:${REMOTE_FILE}"
