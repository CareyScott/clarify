# Clarify

Tidy up text you already wrote, without it stopping sounding like you.

Select text in any app and run Clarify. A small black panel opens by the pointer with your text as an inline diff: struck-through words are what Claude would take out, highlighted words are what it would put in. A line above says what changed and what is still unclear. Press ⌘↩ and the selection is replaced.

It fixes spelling, grammar and punctuation, and makes the idea land. It does not add ideas, greetings or sign-offs, and it does not make you sound formal. Use it on a Slack reply before you send it, or on a messy note you want to think through.

## Talking back

Type under the diff and press Return:

- "skip the change to the second sentence"
- "keep 'aswell', that's how the team writes it"
- "add that the fix is already on master"
- "is this too blunt for a partner?"

Each instruction stays in force for the next ones. A question gets an answer in the notes and leaves the text alone. Press Return on an empty field to try again.

To give Claude something to look at, such as the thread you are replying to, paste an image with ⌘V or press the camera button for a screenshot of the display under the pointer. Each image shows as a small square above the input. Click a square to preview it, click its × to remove it. Images go with every turn until removed.

Keys: Return sends, ⌘↩ replaces the selection, Esc closes.

## Your voice

Clarify reads `~/.config/clarify/voice.md` into every request. Write down how you write: length, tone, spelling, habits to keep, things you never say. A few real examples help most. `voice.example.md` is the starting template, and the install copies it there if the file is missing.

## Install

Needs macOS, Claude Code signed in, and `swiftc` from the Xcode command line tools.

```sh
./install.sh
```

This builds the app into `build/Clarify`, runs the diff tests, links `clarify-selection` into `~/.local/bin`, and installs a Clarify Quick Action.

Ways to run it:

- Right-click selected text > Services > Clarify. Give it a hotkey in System Settings > Keyboard > Keyboard Shortcuts > Services > Text.
- Raycast: add `raycast/` as a Script Directory, or install with `RAYCAST_SCRIPTS_DIR=<dir> ./install.sh`.
- Any launcher or shell: `clarify-selection`. It reads stdin when piped, otherwise it copies the current selection.

## Permissions

The app that launches Clarify (Raycast, the Services runner, your terminal) needs:

- Accessibility, to paste the result back over the selection. Without it the result is copied and you press ⌘V yourself. `clarify-selection` also needs it to copy the selection when nothing is piped in.
- Screen Recording, only for the camera button.

## Settings

Clarify uses Sonnet. Set `CLARIFY_MODEL` to use another model, for example `opus`.

## How it works

`bin/clarify-selection` gets the text and starts `build/Clarify`, a single AppKit binary with no Dock icon. The panel is non-activating, so the app you were in stays in front and keeps its selection.

Every turn runs `claude -p` with no tools, no settings, no MCP servers and no saved session. The request carries the original text, the current draft, every instruction so far, and any attached images, scaled down to 1568px on the longest side. Claude replies with `<notes>` and `<text>`. The diff is always against the original, so you see the full change at once.

Replacing the selection puts the result on the clipboard, sends ⌘V to the front app, and puts your old clipboard text back.

## Development

```sh
swiftc -O -o build/Clarify Sources/*.swift -framework AppKit
swiftc -o build/word-diff-tests Sources/WordDiff.swift Tests/main.swift && build/word-diff-tests
printf 'teh text to tidy' | build/Clarify
```
