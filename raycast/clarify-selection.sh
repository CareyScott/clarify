#!/usr/bin/env bash

# @raycast.schemaVersion 1
# @raycast.title Clarify
# @raycast.mode silent
# @raycast.packageName Clarify
# @raycast.icon ✍️
# @raycast.description Tidy the selected text in your own voice

exec "$(dirname "$(readlink -f "$0")")/../bin/clarify-selection"
