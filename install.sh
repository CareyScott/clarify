#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$HOME/.config/clarify"

command -v swiftc >/dev/null || { echo "swiftc is required (xcode-select --install)"; exit 1; }
command -v claude >/dev/null || [ -x "$HOME/.local/bin/claude" ] || { echo "Claude Code is required"; exit 1; }

cd "$ROOT"
mkdir -p build
swiftc -O -o build/Clarify Sources/*.swift -framework AppKit
swiftc -o build/word-diff-tests Sources/WordDiff.swift Tests/main.swift
build/word-diff-tests >/dev/null || { build/word-diff-tests; exit 1; }
chmod +x bin/clarify-selection raycast/clarify-selection.sh

mkdir -p "$CONFIG_DIR"
[ -f "$CONFIG_DIR/voice.md" ] || cp voice.example.md "$CONFIG_DIR/voice.md"

mkdir -p "$HOME/.local/bin"
ln -sf "$ROOT/bin/clarify-selection" "$HOME/.local/bin/clarify-selection"

bash "$ROOT/services/install-quick-action.sh"

if [ -n "${RAYCAST_SCRIPTS_DIR:-}" ]; then
  mkdir -p "$RAYCAST_SCRIPTS_DIR"
  ln -sf "$ROOT/raycast/clarify-selection.sh" "$RAYCAST_SCRIPTS_DIR/clarify-selection.sh"
  RAYCAST_NOTE="linked into $RAYCAST_SCRIPTS_DIR"
else
  RAYCAST_NOTE="add $ROOT/raycast as a Script Directory in Raycast, or rerun with RAYCAST_SCRIPTS_DIR=<dir>"
fi

cat <<MSG

Installed.
  App:          $ROOT/build/Clarify
  Voice:        $CONFIG_DIR/voice.md
  Command:      clarify-selection
  Quick Action: right-click selected text > Services > Clarify
  Raycast:      Clarify ($RAYCAST_NOTE)
MSG
