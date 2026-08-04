#!/usr/bin/env bash
# Install Ziva AI into this Godot project (macOS universal build).
# Source: https://store.godotengine.org/asset/ziva/ziva/
# Manual alternative: https://ziva.sh/download

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="v3.1.2"
URL="https://github.com/ziva-sh/ziva-agent-plugin-godot/releases/download/${VERSION}/ziva-ai-agent-${VERSION}-godot-v4.2.0-macos-universal.zip"
TMP="$(mktemp -d)"

echo "Downloading Ziva ${VERSION} (macOS universal)..."
curl -fsSL -o "$TMP/ziva.zip" "$URL"
unzip -q "$TMP/ziva.zip" -d "$ROOT"
rm -rf "$TMP"

if [ ! -f "$ROOT/addons/ziva_agent/ziva_agent.gdextension" ]; then
	echo "Install failed: addons/ziva_agent/ziva_agent.gdextension missing" >&2
	exit 1
fi

echo "Ziva installed to $ROOT/addons/ziva_agent/"
echo "Open godot/project.godot in Godot 4.7+, restart if needed, then sign in via the Ziva panel."
