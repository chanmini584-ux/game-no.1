#!/usr/bin/env bash
# 개발 환경 구성: 소프트웨어 Vulkan(lavapipe) + Godot 바이너리. 여러 번 실행해도 안전하다.
set -euo pipefail
GODOT_VERSION="4.6-stable"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$ROOT/tools/bin"
GODOT="$BIN_DIR/godot"

if [ ! -f /usr/share/vulkan/icd.d/lvp_icd.json ]; then
  apt-get install -y -q mesa-vulkan-drivers >/dev/null 2>&1 \
    || { apt-get update -q >/dev/null 2>&1 && apt-get install -y -q mesa-vulkan-drivers >/dev/null 2>&1; }
fi
command -v xvfb-run >/dev/null || apt-get install -y -q xvfb >/dev/null 2>&1

if [ ! -x "$GODOT" ]; then
  mkdir -p "$BIN_DIR"
  tmp="$(mktemp -d)"
  curl -sSfL -o "$tmp/godot.zip" \
    "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip"
  unzip -oq "$tmp/godot.zip" -d "$tmp"
  mv "$tmp/Godot_v${GODOT_VERSION}_linux.x86_64" "$GODOT"
  chmod +x "$GODOT"
  rm -rf "$tmp"
fi

"$GODOT" --version
