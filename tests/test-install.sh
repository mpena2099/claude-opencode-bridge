#!/usr/bin/env bash

set -euo pipefail

TARGET_SKILL="$HOME/.claude/skills/delegate-to-opencode/SKILL.md"
TARGET_WORKER="$HOME/.local/bin/claude-opencode-worker"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

[[ -f "$TARGET_SKILL" ]] || fail "Missing skill: $TARGET_SKILL"
[[ -x "$TARGET_WORKER" ]] || fail "Missing or non-executable worker: $TARGET_WORKER"

grep -Fq 'name: delegate-to-opencode' "$TARGET_SKILL" || fail "Skill name is missing"
grep -Fq 'current main model is Opus' "$TARGET_SKILL" || fail "Opus rule is missing"
grep -Fq 'current model is Sonnet' "$TARGET_SKILL" || fail "Sonnet rule is missing"
grep -Fq 'opencode' "$TARGET_WORKER" || fail "OpenCode invocation is missing"

if command -v opencode >/dev/null 2>&1; then
    echo "PASS: bridge files are installed."
    echo "OpenCode: $(opencode --version)"
else
    echo "PASS: bridge files are installed."
    echo "NOTE: opencode is not currently in PATH."
fi
