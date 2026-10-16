#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_SKILL="$REPO_DIR/skills/delegate-to-opencode/SKILL.md"
SOURCE_WORKER="$REPO_DIR/skills/delegate-to-opencode/scripts/claude-opencode-worker"
SOURCE_CHECKLIST="$REPO_DIR/skills/delegate-to-opencode/references/review-checklist.md"
SOURCE_REFERENCE="$REPO_DIR/skills/delegate-to-opencode/references/worker.md"
SOURCE_COMMAND="$REPO_DIR/commands/delegate.md"

TARGET_SKILL="$HOME/.claude/skills/delegate-to-opencode/SKILL.md"
TARGET_WORKER="$HOME/.claude/skills/delegate-to-opencode/scripts/claude-opencode-worker"
TARGET_CHECKLIST="$HOME/.claude/skills/delegate-to-opencode/references/review-checklist.md"
TARGET_REFERENCE="$HOME/.claude/skills/delegate-to-opencode/references/worker.md"
TARGET_COMMAND="$HOME/.claude/commands/delegate.md"
LEGACY_WORKER="$HOME/.local/bin/claude-opencode-worker"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

[[ -f "$TARGET_SKILL" ]] || fail "Missing skill: $TARGET_SKILL"
[[ -x "$TARGET_WORKER" ]] || fail "Missing or non-executable worker: $TARGET_WORKER"
[[ -f "$TARGET_CHECKLIST" ]] || fail "Missing checklist: $TARGET_CHECKLIST"
[[ -f "$TARGET_REFERENCE" ]] || fail "Missing reference: $TARGET_REFERENCE"

cmp -s "$SOURCE_SKILL" "$TARGET_SKILL" || fail "Installed skill differs from the repository; run ./install.sh"
cmp -s "$SOURCE_WORKER" "$TARGET_WORKER" || fail "Installed worker differs from the repository; run ./install.sh"
cmp -s "$SOURCE_CHECKLIST" "$TARGET_CHECKLIST" || fail "Installed checklist differs from the repository; run ./install.sh"
cmp -s "$SOURCE_REFERENCE" "$TARGET_REFERENCE" || fail "Installed reference differs from the repository; run ./install.sh"
cmp -s "$SOURCE_COMMAND" "$TARGET_COMMAND" || fail "Installed /delegate command differs from the repository; run ./install.sh"

if [[ -e "$LEGACY_WORKER" || -L "$LEGACY_WORKER" ]]; then
    fail "Legacy worker still exists: $LEGACY_WORKER"
fi

# Collapse whitespace so line wrapping in the YAML description does not matter.
FLAT_SKILL="$(tr -s '[:space:]' ' ' < "$SOURCE_SKILL")"

grep -Eq '^name: delegate-to-opencode$' "$SOURCE_SKILL" || fail "Skill name is missing"
grep -Fq 'current main model is Opus' <<< "$FLAT_SKILL" || fail "Opus rule is missing"
grep -Fq 'current model is Sonnet' <<< "$FLAT_SKILL" || fail "Sonnet rule is missing"

REPO_VERSION="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$REPO_DIR/VERSION")"
SKILL_VERSION="$(sed -n '/^metadata:/,/^---$/p' "$SOURCE_SKILL" | grep -E '^[[:space:]]*version:' | sed -e 's/^[[:space:]]*version:[[:space:]]*//' -e 's/[[:space:]]*$//' || true)"
[[ -n "$SKILL_VERSION" ]] || fail "Skill version is missing"
[[ "$SKILL_VERSION" == "$REPO_VERSION" ]] || fail "Skill version $SKILL_VERSION differs from VERSION $REPO_VERSION"

echo "PASS: bridge files are installed and match the repository."
if command -v opencode >/dev/null 2>&1; then
    echo "OpenCode: $(opencode --version)"
else
    echo "NOTE: opencode is not currently in PATH."
fi
