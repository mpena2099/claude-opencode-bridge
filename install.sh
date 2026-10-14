#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SKILL="$SCRIPT_DIR/skills/delegate-to-opencode/SKILL.md"
SOURCE_WORKER="$SCRIPT_DIR/skills/delegate-to-opencode/scripts/claude-opencode-worker"
SOURCE_CHECKLIST="$SCRIPT_DIR/skills/delegate-to-opencode/references/review-checklist.md"

TARGET_SKILL="$HOME/.claude/skills/delegate-to-opencode/SKILL.md"
TARGET_WORKER="$HOME/.claude/skills/delegate-to-opencode/scripts/claude-opencode-worker"
TARGET_CHECKLIST="$HOME/.claude/skills/delegate-to-opencode/references/review-checklist.md"
LEGACY_WORKER="$HOME/.local/bin/claude-opencode-worker"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/.claude-opencode-bridge-backups/$TIMESTAMP"

backup_if_exists() {
    local target="$1"
    if [[ -e "$target" || -L "$target" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp -a "$target" "$BACKUP_DIR/"
        echo "Backed up: $target -> $BACKUP_DIR/$(basename "$target")"
    fi
}

backup_if_exists "$TARGET_SKILL"
backup_if_exists "$TARGET_WORKER"
backup_if_exists "$TARGET_CHECKLIST"

mkdir -p "$(dirname "$TARGET_SKILL")" "$(dirname "$TARGET_WORKER")" "$(dirname "$TARGET_CHECKLIST")"

install -m 0644 "$SOURCE_SKILL" "$TARGET_SKILL"
install -m 0755 "$SOURCE_WORKER" "$TARGET_WORKER"
install -m 0644 "$SOURCE_CHECKLIST" "$TARGET_CHECKLIST"

if [[ -e "$LEGACY_WORKER" || -L "$LEGACY_WORKER" ]]; then
    backup_if_exists "$LEGACY_WORKER"
    rm -f "$LEGACY_WORKER"
    echo "Removed legacy worker: $LEGACY_WORKER"
fi

echo
echo "Installed Claude Code → OpenCode bridge."
echo "Skill:  $TARGET_SKILL"
echo "Worker: $TARGET_WORKER"
echo "Checklist: $TARGET_CHECKLIST"
if [[ -d "$BACKUP_DIR" ]]; then
    echo "Backup: $BACKUP_DIR"
fi

echo
echo "Extra deny rules can go in ~/.config/claude-opencode-worker/deny (one shell glob per line)."

echo
echo "Run tests with:"
echo "  ./tests/test-install.sh"
