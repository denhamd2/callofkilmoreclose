#!/usr/bin/env bash
# Styloo Guns Asset Pack — already vendored under godot/assets/weapons/styloo/
#
# Source: https://store.godotengine.org/asset/styloo/guns/
# Alternate download: https://styloo.itch.io/guns-asset-pack
#
# To refresh from itch.io, download "Styloo Guns Asset Pack GLTF FBX V1.1.zip"
# and copy the .glb files into godot/assets/weapons/styloo/, then open the project
# in Godot once so imports regenerate.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$ROOT/godot/assets/weapons/styloo"
mkdir -p "$DEST"
COUNT="$(find "$DEST" -maxdepth 1 -name '*.glb' | wc -l | tr -d ' ')"
echo "Styloo guns: $COUNT GLB(s) in $DEST"
if [[ "$COUNT" -lt 5 ]]; then
	echo "Pack looks incomplete — download from itch.io and copy GLBs into $DEST"
	exit 1
fi
echo "OK"
