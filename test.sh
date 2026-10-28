#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== 1. Validating Lua Syntax ==="
for f in $(find wx_autoharvester -name '*.lua' | sort); do
    echo -n "  $f ... "
    luac -p "$f"
    echo "OK"
done

echo ""
echo "=== 2. Running Automated Mod Test Harness ==="
lua tests/test_mod.lua
