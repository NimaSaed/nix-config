#!/usr/bin/env bash
set -o nounset # Treat unset variables as an error


nix run nixpkgs#colmena -- apply
