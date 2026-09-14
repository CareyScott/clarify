#!/usr/bin/env bash

# @raycast.schemaVersion 1
# @raycast.title Clarify Settings
# @raycast.mode silent
# @raycast.packageName Clarify
# @raycast.icon clarify-icons/settings.png
# @raycast.description Set the scratch pad hotkey, the Claude model and your voice guide
# @raycast.author Scott Carey
# @raycast.authorURL https://github.com/CareyScott

exec "$(dirname "$(readlink -f "$0")")/../bin/clarify-settings"
