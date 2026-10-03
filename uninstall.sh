#!/usr/bin/env bash

set -euo pipefail

TARGET_SKILL="$HOME/.claude/skills/delegate-to-opencode/SKILL.md"
TARGET_WORKER="$HOME/.local/bin/claude-opencode-worker"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/.claude-opencode-bridge-backups/uninstall-$TIMESTAMP"

backup_if_exists() {
    local target="$1"
    if [[ -e "$target" || -L "$target" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp -a "$target" "$BACKUP_DIR/"
        rm -f "$target"
        echo "Removed: $target"
    fi
}

backup_if_exists "$TARGET_SKILL"
backup_if_exists "$TARGET_WORKER"

# Only removes the skill directory when empty, so user-added files survive.
rmdir "$(dirname "$TARGET_SKILL")" 2>/dev/null || true

if [[ -d "$BACKUP_DIR" ]]; then
    echo "Backup saved to: $BACKUP_DIR"
else
    echo "Nothing was installed by this bridge at the expected paths."
fi
