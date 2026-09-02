#!/bin/sh
# Start bacon-net with the Nix-provided toolchain.
cd "$(dirname "$0")"
exec nix develop --command mix run --no-halt "$@"
