#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/wx_autoharvester" && pwd)"

find_mods_dir() {
    if [[ -n "${DONT_STARVE_MODS_DIR:-}" ]]; then
        echo "$DONT_STARVE_MODS_DIR"
        return
    fi
    local candidates=(
        "${HOME}/Games/gog/dont-starve/game/mods"
        "${HOME}/.local/share/Steam/steamapps/common/dont_starve/mods"
        "${HOME}/.steam/steam/steamapps/common/dont_starve/mods"
        "${HOME}/.steam/root/steamapps/common/dont_starve/mods"
        "${HOME}/Library/Application Support/Steam/steamapps/common/dont_starve/mods"
    )
    for dir in "${candidates[@]}"; do
        if [[ -d "$dir" ]]; then
            echo "$dir"
            return
        fi
    done
    echo "${HOME}/Games/gog/dont-starve/game/mods"
}

BASE_MODS_DIR="$(find_mods_dir)"
DEST_DIR="${BASE_MODS_DIR}/wx_autoharvester"

mkdir -p "$(dirname "$DEST_DIR")"
rm -rf "$DEST_DIR"
ln -sfn "$SRC_DIR" "$DEST_DIR"

echo "Linked wx_autoharvester -> $DEST_DIR"
