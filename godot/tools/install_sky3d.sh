#!/usr/bin/env bash
# Sky3D — Tokisan Games day/night sky addon (MIT)
# https://store.godotengine.org/asset/tokisangames/sky3d/
# https://github.com/TokisanGames/Sky3D

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$ROOT/godot/addons/sky_3d"
TAG="v2.1.0"
TMP="$(mktemp -d)"

if [[ -d "$DEST" && -f "$DEST/plugin.cfg" ]]; then
  echo "Sky3D already present at $DEST"
  exit 0
fi

echo "Cloning Sky3D $TAG..."
git clone --depth 1 --branch "$TAG" https://github.com/TokisanGames/Sky3D.git "$TMP/sky3d"

if [[ ! -d "$TMP/sky3d/addons/sky_3d" ]]; then
  echo "Expected addons/sky_3d in clone — check tag $TAG" >&2
  exit 1
fi

rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
cp -R "$TMP/sky3d/addons/sky_3d" "$DEST"
rm -rf "$TMP"

echo "OK — installed Sky3D to $DEST"
