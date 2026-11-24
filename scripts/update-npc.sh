#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

base=https://artifactory.nebius.dev/artifactory/npc
file=pkgs/nebius-cli/npc.nix

version=$(curl -fsS --max-time 10 "$base/release/stable")
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "unexpected version: $version" >&2; exit 1; }

sha256=$(curl -fsS --max-time 10 "$base/release/$version/linux/x86_64/npc.sha256")
hash=$(nix hash convert --hash-algo sha256 --to sri "$sha256")

sed -i -E "s|version = \".*\"|version = \"$version\"|; s|hash = \".*\"|hash = \"$hash\"|" "$file"

echo "npc pinned to $version"
