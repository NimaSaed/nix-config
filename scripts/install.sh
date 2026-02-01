#!/usr/bin/env bash
set -euo pipefail

# Usage: ./install.sh [--mount-only] <remote-host>

MOUNT_ONLY=false
if [[ "${1:-}" == "--mount-only" ]]; then
    MOUNT_ONLY=true
    shift
fi

REMOTE_HOST="${1:?Usage: $0 [--mount-only] <remote-host>}"

# Extract hostname from REMOTE_HOST (e.g., root@chestnut.nmsd.xyz -> chestnut)
HOST_PART="${REMOTE_HOST#*@}"
HOSTNAME="${HOST_PART%%.*}"

# Derive 1Password item name from hostname (e.g., chestnut -> Chestnut SOPS Age)
HOSTNAME_CAPITALIZED="$(echo "${HOSTNAME:0:1}" | tr '[:lower:]' '[:upper:]')${HOSTNAME:1}"
OP_ITEM="${HOSTNAME_CAPITALIZED} SOPS Age"

FLAKE_TARGET="$HOSTNAME"

# Extract disk device paths from the host's disko configuration
echo "Reading disk configuration for $FLAKE_TARGET..."
DISK_DEVICES_JSON=$(nix eval --json ".#nixosConfigurations.${FLAKE_TARGET}.config.disko.devices.disk" \
    --apply 'builtins.mapAttrs (name: disk: disk.device)')
readarray -t DISK_DEVICES < <(echo "$DISK_DEVICES_JSON" | jq -r '.[]')

if [[ ${#DISK_DEVICES[@]} -eq 0 ]]; then
    echo "Error: No disk devices found in disko config for $FLAKE_TARGET"
    exit 1
fi

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

DISKO_ARGS=()

if [[ "$MOUNT_ONLY" == true ]]; then
    echo "Mode: mount-only (re-install without reformatting)"
    DISKO_ARGS+=(--disko-mode mount)
else
    echo ""
    echo "⚠  WARNING: This will ERASE ALL DATA on the following disks on $REMOTE_HOST:"
    for dev in "${DISK_DEVICES[@]}"; do
        echo "   - $dev"
    done
    echo ""
    read -r -p "Type 'yes' to continue: " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "Aborted."
        exit 1
    fi

    # Wipe all disks before nixos-anywhere runs.
    # Disko's built-in deactivation only wipes whole-disk signatures, but after
    # repartitioning, stale filesystem/swap signatures at partition offsets
    # survive and cause disko to skip ZFS pool creation.
    # We destroy ZFS pools first (frees busy devices), then wipe each disk
    # using the appropriate strategy for its type.
    echo "Wiping disks on $REMOTE_HOST..."
    DEVICES_LIST=$(printf '%s\n' "${DISK_DEVICES[@]}")
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$REMOTE_HOST" bash -s <<WIPE_EOF
set -euo pipefail
# Destroy any existing ZFS pools to release device references
for pool in \$(zpool list -H -o name 2>/dev/null || true); do
    echo "Destroying ZFS pool: \$pool"
    zpool destroy -f "\$pool"
done

# Wipe each disk: NVMe gets blkdiscard (instant TRIM), others get wipefs + dd
while IFS= read -r dev; do
    if [[ "\$dev" == */nvme-* ]]; then
        echo "Discarding \$dev (NVMe TRIM)"
        blkdiscard -f "\$dev"
    else
        echo "Wiping \$dev"
        wipefs --all --force "\$dev"
        dd if=/dev/zero of="\$dev" bs=1M count=2048 status=progress
    fi
done <<< "$DEVICES_LIST"

echo "All disks wiped successfully."
WIPE_EOF
fi

echo "Installing NixOS to $REMOTE_HOST with SOPS key..."
nix run github:nix-community/nixos-anywhere/1.13.0 -- \
    --build-on remote \
    --extra-files "$temp" \
    "${DISKO_ARGS[@]}" \
    --flake ".#$FLAKE_TARGET" \
    "$REMOTE_HOST"
