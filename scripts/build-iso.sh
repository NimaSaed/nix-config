#!/usr/bin/env bash
# Build installer ISO based on system architecture
# Works on fresh NixOS installations without flakes configured

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get flake directory (parent of scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Verify flake.nix exists
if [[ ! -f "${FLAKE_DIR}/flake.nix" ]]; then
    echo -e "${RED}Error: flake.nix not found in ${FLAKE_DIR}${NC}"
    exit 1
fi

# Detect architecture
ARCH="$(uname -m)"

echo -e "${YELLOW}Detected architecture:${NC} ${ARCH}"

case "${ARCH}" in
    x86_64)
        TARGET="installer-iso"
        echo -e "${GREEN}Building x86_64 installer ISO...${NC}"
        ;;
    aarch64)
        TARGET="rpi-installer"
        echo -e "${GREEN}Building ARM64 (Raspberry Pi) SD image...${NC}"
        ;;
    *)
        echo -e "${RED}Error: Unsupported architecture '${ARCH}'${NC}"
        echo "Supported architectures: x86_64, aarch64"
        exit 1
        ;;
esac

echo -e "${YELLOW}Running:${NC} nix build ${FLAKE_DIR}#${TARGET}"
echo ""

# Build with experimental features enabled (works on fresh NixOS)
nix --extra-experimental-features "nix-command flakes" build "${FLAKE_DIR}#${TARGET}"

echo ""
echo -e "${GREEN}Build complete!${NC}"
echo -e "Output: ${FLAKE_DIR}/result/"

# Show the built artifact
if [[ -d "${FLAKE_DIR}/result" ]]; then
    echo ""
    echo "Built artifacts:"
    ls -lh "${FLAKE_DIR}/result/"* 2>/dev/null || ls -lh "${FLAKE_DIR}/result/"
fi
