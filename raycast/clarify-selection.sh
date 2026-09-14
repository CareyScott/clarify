#!/usr/bin/env bash

# @raycast.schemaVersion 1
# @raycast.title Clarify Selection
# @raycast.mode silent
# @raycast.packageName Clarify
# @raycast.icon clarify-icons/clarify.png
# @raycast.description Tidy the selected text in your own voice, with an inline diff and a chat to steer it
# @raycast.author Scott Carey
# @raycast.authorURL https://github.com/CareyScott

exec "$(dirname "$(readlink -f "$0")")/../bin/clarify-selection"
