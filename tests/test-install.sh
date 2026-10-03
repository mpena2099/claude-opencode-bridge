#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_SKILL="$REPO_DIR/skills/delegate-to-opencode/SKILL.md"
SOURCE_WORKER="$REPO_DIR/bin/claude-opencode-worker"

TARGET_SKILL="$HOME/.claude/skills/delegate-to-opencode/SKILL.md"
TARGET_WORKER="$HOME/.local/bin/claude-opencode-worker"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

[[ -f "$TARGET_SKILL" ]] || fail "Missing skill: $TARGET_SKILL"
[[ -x "$TARGET_WORKER" ]] || fail "Missing or non-executable worker: $TARGET_WORKER"

cmp -s "$SOURCE_SKILL" "$TARGET_SKILL" || fail "Installed skill differs from the repository; run ./install.sh"
cmp -s "$SOURCE_WORKER" "$TARGET_WORKER" || fail "Installed worker differs from the repository; run ./install.sh"

# Collapse whitespace so line wrapping in the YAML description does not matter.
FLAT_SKILL="$(tr -s '[:space:]' ' ' < "$SOURCE_SKILL")"

grep -Eq '^name: delegate-to-opencode$' "$SOURCE_SKILL" || fail "Skill name is missing"
grep -Fq 'current main model is Opus' <<< "$FLAT_SKILL" || fail "Opus rule is missing"
grep -Fq 'current model is Sonnet' <<< "$FLAT_SKILL" || fail "Sonnet rule is missing"

echo "PASS: bridge files are installed and match the repository."
if command -v opencode >/dev/null 2>&1; then
    echo "OpenCode: $(opencode --version)"
else
    echo "NOTE: opencode is not currently in PATH."
fi
