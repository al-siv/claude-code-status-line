#!/usr/bin/env bash
# Copies statusline.sh into ~/.claude and prints the settings.json snippet.
set -euo pipefail

src="$(cd "$(dirname "$0")" && pwd)/statusline.sh"
dest="$HOME/.claude/statusline.sh"

mkdir -p "$HOME/.claude"
cp "$src" "$dest"
chmod +x "$dest"

printf 'Installed: %s\n\n' "$dest"
printf 'Add this to %s/.claude/settings.json:\n\n' "$HOME"
cat <<'JSON'
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh"
  }
JSON
