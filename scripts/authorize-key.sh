#!/usr/bin/env bash
# Helper script to add Nima's SSH public key to current user's authorized_keys

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_KEY_FILE="$SCRIPT_DIR/../home/nima/ssh.pub"

# Check if the SSH key file exists
if [[ ! -f "$SSH_KEY_FILE" ]]; then
    echo "Error: SSH key file not found at $SSH_KEY_FILE"
    exit 1
fi

# Read the SSH public key
SSH_KEY=$(cat "$SSH_KEY_FILE")

# Create .ssh directory if it doesn't exist
if [[ ! -d "$HOME/.ssh" ]]; then
    echo "Creating $HOME/.ssh directory..."
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
fi

# Create authorized_keys file if it doesn't exist
if [[ ! -f "$HOME/.ssh/authorized_keys" ]]; then
    echo "Creating $HOME/.ssh/authorized_keys file..."
    touch "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
fi

# Check if the key is already in authorized_keys
if grep -qF "$SSH_KEY" "$HOME/.ssh/authorized_keys" 2>/dev/null; then
    echo "SSH key is already authorized for user $(whoami)"
    exit 0
fi

# Add the key to authorized_keys
echo "Adding SSH key to $HOME/.ssh/authorized_keys..."
echo "$SSH_KEY" >> "$HOME/.ssh/authorized_keys"

# Ensure proper permissions
chmod 600 "$HOME/.ssh/authorized_keys"
chmod 700 "$HOME/.ssh"

echo "✓ SSH key successfully added for user $(whoami)"
echo "  You can now SSH to this machine using your private key"
