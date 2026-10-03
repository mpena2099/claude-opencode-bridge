#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SKILL="$SCRIPT_DIR/skills/delegate-to-opencode/SKILL.md"
SOURCE_WORKER="$SCRIPT_DIR/bin/claude-opencode-worker"

TARGET_SKILL="$HOME/.claude/skills/delegate-to-opencode/SKILL.md"
TARGET_WORKER="$HOME/.local/bin/claude-opencode-worker"

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

mkdir -p "$(dirname "$TARGET_SKILL")" "$(dirname "$TARGET_WORKER")"

install -m 0644 "$SOURCE_SKILL" "$TARGET_SKILL"
install -m 0755 "$SOURCE_WORKER" "$TARGET_WORKER"

echo
echo "Installed Claude Code → OpenCode bridge."
echo "Skill:  $TARGET_SKILL"
echo "Worker: $TARGET_WORKER"
if [[ -d "$BACKUP_DIR" ]]; then
    echo "Backup: $BACKUP_DIR"
fi

echo
echo "Run tests with:"
echo "  ./tests/test-install.sh"
