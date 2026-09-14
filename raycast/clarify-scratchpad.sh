#!/usr/bin/env bash

# @raycast.schemaVersion 1
# @raycast.title Clarify Scratch Pad
# @raycast.mode silent
# @raycast.packageName Clarify
# @raycast.icon clarify-icons/scratchpad.png
# @raycast.description Open a scratch pad to type or dictate a draft, then clarify it in your own voice
# @raycast.author Scott Carey
# @raycast.authorURL https://github.com/CareyScott

exec "$(dirname "$(readlink -f "$0")")/../bin/clarify-scratchpad"
