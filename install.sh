#!/usr/bin/env bash
# Copies statusline.sh into ~/.claude and prints the settings.json snippet.
set -euo pipefail

src="$(cd "$(dirname "$0")" && pwd)/statusline.sh"
dest="$HOME/.claude/statusline.sh"

mkdir -p "$HOME/.claude"
# Keep an existing, different status-line script instead of overwriting it.
if [ -e "$dest" ] && ! cmp -s "$src" "$dest"; then
  backup="$dest.bak.$(date +%Y%m%d%H%M%S)"
  mv "$dest" "$backup"
  printf 'Backed up existing %s to %s\n' "$dest" "$backup"
fi
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
