#!/usr/bin/env bash
set -euo pipefail

ICONS_DIR="Sources/CodexBarLinux/Resources/icons"
mkdir -p "$ICONS_DIR"

# slug -> filename mapping (all fetched as white SVG on transparent bg)
declare -A ICONS=(
    ["anthropic"]="claude.svg"
    ["openai"]="codex.svg"
    ["cursor"]="cursor.svg"
    ["githubcopilot"]="copilot.svg"
    ["openrouter"]="openrouter.svg"
    ["jetbrains"]="jetbrains.svg"
    ["opencode"]="opencode.svg"
)

BASE_URL="https://cdn.simpleicons.org"

for slug in "${!ICONS[@]}"; do
    filename="${ICONS[$slug]}"
    dest="$ICONS_DIR/$filename"
    if [ ! -f "$dest" ]; then
        echo "Downloading $slug -> $filename"
        curl -sf "$BASE_URL/$slug/ffffff" -o "$dest" || {
            echo "  WARNING: $slug not found in Simple Icons, skipping"
            rm -f "$dest"
        }
    else
        echo "  $filename already present, skipping"
    fi
done

echo "Icons ready in $ICONS_DIR"
