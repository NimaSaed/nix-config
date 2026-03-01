#!/usr/bin/env bash
set -euo pipefail

# Usage: ./install.sh [--mount-only] [--no-disko-deps] [--build-on-target | --builder <user@host>] <remote-host>

# Nix distributed builder settings (used when --builder <host> is passed)
# Builder spec format: uri  systems  ssh-identity  max-jobs  speed-factor  supported-features  mandatory-features
# ssh-identity: path to SSH private key, or "-" to use the default SSH agent / known keys
BUILDER_SSH_KEY="-"
# max-jobs: parallel build jobs on the remote builder
BUILDER_MAX_JOBS="4"
# speed-factor: relative preference when multiple builders are available (higher = more preferred)
BUILDER_SPEED_FACTOR="1"
# supported-features: capabilities the builder supports
#   nixos-test   - can run NixOS VM tests
#   benchmark    - can run benchmarks
#   big-parallel - can handle large parallel derivations (recommended for servers)
#   kvm          - has KVM virtualisation support (required to actually run nixos-test VMs)
BUILDER_FEATURES="nixos-test,benchmark,big-parallel,kvm"

MOUNT_ONLY=false
NO_DISKO_DEPS=false
BUILD_ON_TARGET=false
BUILD_HOST=""

while [[ "${1:-}" == --* ]]; do
    case "${1:-}" in
        --mount-only)      MOUNT_ONLY=true; shift ;;
        --no-disko-deps)   NO_DISKO_DEPS=true; shift ;;
        --build-on-target) BUILD_ON_TARGET=true; shift ;;
        --builder)         BUILD_HOST="${2:?--builder requires a value (e.g. root@host)}"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

REMOTE_HOST="${1:?Usage: $0 [--mount-only] [--no-disko-deps] [--build-on-target | --builder <user@host>] <user@host>}"

if [[ "$BUILD_ON_TARGET" == true && -n "$BUILD_HOST" ]]; then
    echo "Error: --build-on-target and --builder are mutually exclusive"
    exit 1
fi

# Extract hostname from REMOTE_HOST (e.g., root@chestnut.nmsd.xyz -> chestnut)
HOST_PART="${REMOTE_HOST#*@}"
HOSTNAME="${HOST_PART%%.*}"

# Derive 1Password item name from hostname (e.g., chestnut -> Chestnut SOPS Age)
HOSTNAME_CAPITALIZED="$(echo "${HOSTNAME:0:1}" | tr '[:lower:]' '[:upper:]')${HOSTNAME:1}"
OP_ITEM="${HOSTNAME_CAPITALIZED} SOPS Age"

FLAKE_TARGET="$HOSTNAME"

# Read target system architecture from flake (e.g. x86_64-linux, aarch64-linux)
TARGET_SYSTEM=$(nix eval --raw ".#nixosConfigurations.${FLAKE_TARGET}.config.nixpkgs.system")

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

BUILD_ARGS=()
if [[ "$BUILD_ON_TARGET" == true ]]; then
    BUILD_ARGS+=(--build-on remote)
elif [[ -n "$BUILD_HOST" ]]; then
    BUILD_ARGS+=(--option builders \
        "ssh://$BUILD_HOST $TARGET_SYSTEM $BUILDER_SSH_KEY $BUILDER_MAX_JOBS $BUILDER_SPEED_FACTOR $BUILDER_FEATURES")
else
    BUILD_ARGS+=(--build-on local)
fi

EXTRA_ARGS=()
if [[ "$NO_DISKO_DEPS" == true ]]; then
    # Skip uploading disko tool dependencies (parted, zfs, mdadm, etc.) into the kexec
    # installer RAM. Safe only when the target has no ZFS/exotic filesystems, since the
    # kexec environment's built-in tools must already cover all disko operations.
    EXTRA_ARGS+=(--no-disko-deps)
fi

echo "Installing NixOS to $REMOTE_HOST with SOPS key..."
nix run github:nix-community/nixos-anywhere/1.13.0 -- \
    --extra-files "$temp" \
    "${DISKO_ARGS[@]}" \
    "${BUILD_ARGS[@]}" \
    "${EXTRA_ARGS[@]}" \
    --flake ".#$FLAKE_TARGET" \
    "$REMOTE_HOST"
