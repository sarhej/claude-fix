#!/bin/bash
# This script is now called claude-fix. This file keeps old commands and links working.
set -euo pipefail
src="${BASH_SOURCE[0]:-}"
if [ -n "$src" ] && [ -f "$(dirname "$src")/claude-fix" ]; then
  exec "$BASH" "$(dirname "$src")/claude-fix" "$@"
fi
# Piped from curl: fetch the renamed script.
exec "$BASH" -c "$(curl -fsSL https://raw.githubusercontent.com/sarhej/claude-fix/heads/main/claude-fix)" claude-fix "$@"
