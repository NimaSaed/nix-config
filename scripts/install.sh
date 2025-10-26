#!/usr/bin/env bash
set -o nounset # Treat unset variables as an error




nix run github:numtide/nixos-anywhere -- --build-on remote --flake .#server nixos@192.168.1.94
