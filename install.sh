#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$HOME/.config/clarify"

command -v swiftc >/dev/null || { echo "swiftc is required (xcode-select --install)"; exit 1; }
command -v claude >/dev/null || [ -x "$HOME/.local/bin/claude" ] || { echo "Claude Code is required"; exit 1; }

cd "$ROOT"
mkdir -p build
SETTINGS_APP="build/Clarify Settings.app"
rm -rf build/Clarify.app build/Clarify "$SETTINGS_APP"
mkdir -p build/Clarify.app/Contents/MacOS "$SETTINGS_APP/Contents/MacOS"
cp Resources/Info.plist build/Clarify.app/Contents/Info.plist
cp Resources/Settings-Info.plist "$SETTINGS_APP/Contents/Info.plist"
mkdir -p build/Clarify.app/Contents/Resources "$SETTINGS_APP/Contents/Resources"
cp Resources/Clarify.icns build/Clarify.app/Contents/Resources/Clarify.icns
cp Resources/ClarifySettings.icns "$SETTINGS_APP/Contents/Resources/ClarifySettings.icns"
swiftc -O -o build/Clarify.app/Contents/MacOS/Clarify Sources/*.swift Shared/*.swift -framework AppKit -framework Carbon
swiftc -O -o "$SETTINGS_APP/Contents/MacOS/ClarifySettings" Settings/*.swift Shared/*.swift -framework AppKit -framework SwiftUI -framework Carbon
codesign --force --sign - build/Clarify.app >/dev/null 2>&1
codesign --force --sign - "$SETTINGS_APP" >/dev/null 2>&1
rm -f build/ClarifyHotkey
swiftc -o build/tests Sources/WordDiff.swift Shared/HotkeyCombination.swift Shared/HotkeyConflicts.swift Settings/HotkeyText.swift Tests/main.swift -framework AppKit -framework Carbon
build/tests >/dev/null || { build/tests; exit 1; }
chmod +x bin/clarify-selection bin/clarify-scratchpad bin/clarify-hotkey bin/clarify-settings raycast/clarify-selection.sh raycast/clarify-scratchpad.sh raycast/clarify-settings.sh

mkdir -p "$CONFIG_DIR"
[ -f "$CONFIG_DIR/voice.md" ] || cp voice.example.md "$CONFIG_DIR/voice.md"

mkdir -p "$HOME/.local/bin"
ln -sf "$ROOT/bin/clarify-selection" "$HOME/.local/bin/clarify-selection"
ln -sf "$ROOT/bin/clarify-scratchpad" "$HOME/.local/bin/clarify-scratchpad"
ln -sf "$ROOT/bin/clarify-hotkey" "$HOME/.local/bin/clarify-hotkey"
ln -sf "$ROOT/bin/clarify-settings" "$HOME/.local/bin/clarify-settings"

CONFIGURED_HOTKEY="$(bin/clarify-hotkey | sed -n 's/^Scratch pad hotkey: //p')"
if [ -n "$CONFIGURED_HOTKEY" ]; then
  bin/clarify-hotkey "$CONFIGURED_HOTKEY" >/dev/null
  HOTKEY_NOTE="$CONFIGURED_HOTKEY (listener restarted)"
else
  HOTKEY_NOTE="none set, optional: clarify-hotkey option+c"
fi

bash "$ROOT/services/install-quick-action.sh"

if [ -n "${RAYCAST_SCRIPTS_DIR:-}" ]; then
  mkdir -p "$RAYCAST_SCRIPTS_DIR"
  ln -sf "$ROOT/raycast/clarify-selection.sh" "$RAYCAST_SCRIPTS_DIR/clarify-selection.sh"
  ln -sf "$ROOT/raycast/clarify-scratchpad.sh" "$RAYCAST_SCRIPTS_DIR/clarify-scratchpad.sh"
  ln -sf "$ROOT/raycast/clarify-settings.sh" "$RAYCAST_SCRIPTS_DIR/clarify-settings.sh"
  ln -sfn "$ROOT/raycast/clarify-icons" "$RAYCAST_SCRIPTS_DIR/clarify-icons"
  RAYCAST_NOTE="linked into $RAYCAST_SCRIPTS_DIR"
else
  RAYCAST_NOTE="add $ROOT/raycast as a Script Directory in Raycast, or rerun with RAYCAST_SCRIPTS_DIR=<dir>"
fi

cat <<MSG

Installed.
  App:          $ROOT/build/Clarify.app
  Voice:        $CONFIG_DIR/voice.md
  Settings:     $ROOT/$SETTINGS_APP (or clarify-settings, or the gear in the panel)
  Commands:     clarify-selection, clarify-scratchpad, clarify-hotkey, clarify-settings
  Hotkey:       $HOTKEY_NOTE
  Quick Action: right-click selected text > Services > Clarify
  Raycast:      Clarify Selection, Clarify Scratch Pad, Clarify Settings ($RAYCAST_NOTE)
MSG
