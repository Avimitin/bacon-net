#!/bin/sh
# Syntax-check Elixir source files against the compiled bacon_net beams
# without touching the shared _build tree (safe for parallel use).
# Usage: scripts/check_file.sh lib/bacon_net/modules/<game>/<file>.ex ...
set -e
cd "$(dirname "$0")/.."
mkdir -p /tmp/elixirc_check
exec elixirc -o /tmp/elixirc_check --ignore-module-conflict \
  -pa "$PWD"/_build/dev/lib/bacon_net/ebin \
  -pa "$PWD"/_build/dev/lib/jason/ebin \
  -pa "$PWD"/_build/dev/lib/plug/ebin \
  "$@"
