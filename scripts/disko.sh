#!/usr/bin/env bash
set -o nounset # Treat unset variables as an error


sudo nix \
  --experimental-features "nix-command flakes" \
  run github:nix-community/disko -- \
  --mode destroy,format,mount \
  ./hosts/vm/disko.nix
