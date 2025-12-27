#!/usr/bin/env bash
set -o nounset # Treat unset variables as an error




nix run github:numtide/nixos-anywhere -- --build-on remote --flake .#chestnut root@chestnut.nmsd.xyz
