#!/usr/bin/env bash

# Exercises bin/claude-opencode-worker against a stub `opencode`, so it runs
# without OpenCode installed and without calling any model.

set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORKER="$REPO_DIR/bin/claude-opencode-worker"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/out" "$TMP/repo" "$TMP/plain"
git -C "$TMP/repo" init -q

cat > "$TMP/bin/opencode" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
    echo "0.0.0-stub"
    exit 0
fi
printf '%s\n' "$@" > "$STUB_OUT/args"
printf '%s' "${OPENCODE_CONFIG_CONTENT:-}" > "$STUB_OUT/config"
if [[ -n "${STUB_SLEEP:-}" ]]; then
    sleep "$STUB_SLEEP"
fi
exit "${STUB_EXIT:-0}"
STUB
chmod +x "$TMP/bin/opencode"

export PATH="$TMP/bin:$PATH"
export STUB_OUT="$TMP/out"
unset OPENCODE_CONFIG_CONTENT OPENCODE_WORKER_MODEL OPENCODE_WORKER_TIMEOUT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

run_worker() {
    (cd "$TMP/repo" && "$WORKER" "$@")
}

# Task on stdin keeps shell metacharacters literal.
# shellcheck disable=SC2016
LITERAL='Use $HOME and `date` and "quotes" literally'
run_worker > /dev/null <<< "$LITERAL" || fail "stdin task run failed"
grep -Fq "$LITERAL" "$TMP/out/args" || fail "stdin task was not passed literally"
grep -Fxq -- '--agent' "$TMP/out/args" || fail "--agent build missing"
grep -Fxq -- "$TMP/repo" "$TMP/out/args" || fail "--dir project path missing"

# Task as arguments still works.
run_worker "Create" "file.txt" > /dev/null || fail "argument task run failed"
grep -Fq "Create file.txt" "$TMP/out/args" || fail "argument task was not passed"

# Git deny rules reach OpenCode, including the rtk-rewritten form.
grep -Fq '"*git commit*": "deny"' "$TMP/out/config" || fail "git commit deny rule missing"
grep -Fq '"*git reset*": "deny"' "$TMP/out/config" || fail "git reset deny rule missing"

# A preset OPENCODE_CONFIG_CONTENT is kept and reported.
OPENCODE_CONFIG_CONTENT='{"custom":true}' run_worker "task" > /dev/null 2> "$TMP/err" || fail "preset config run failed"
[[ "$(cat "$TMP/out/config")" == '{"custom":true}' ]] || fail "preset OPENCODE_CONFIG_CONTENT was overwritten"
grep -Fq 'already set' "$TMP/err" || fail "preset config warning missing"

# Model override.
OPENCODE_WORKER_MODEL='provider/model' run_worker "task" > /dev/null || fail "model run failed"
grep -Fxq -- 'provider/model' "$TMP/out/args" || fail "--model override missing"

# Empty task and no task are usage errors.
rc=0; run_worker > /dev/null 2>&1 <<< "   " || rc=$?
[[ $rc -eq 2 ]] || fail "blank task should exit 2, got $rc"
rc=0; run_worker "" > /dev/null 2>&1 || rc=$?
[[ $rc -eq 2 ]] || fail "empty argument should exit 2, got $rc"

# OpenCode exit codes propagate.
rc=0; STUB_EXIT=3 run_worker "task" > /dev/null 2>&1 || rc=$?
[[ $rc -eq 3 ]] || fail "exit code should propagate, got $rc"

# Timeout is reported with exit 124.
rc=0; OPENCODE_WORKER_TIMEOUT=1 STUB_SLEEP=5 run_worker "task" > /dev/null 2> "$TMP/err" || rc=$?
[[ $rc -eq 124 ]] || fail "timeout should exit 124, got $rc"
grep -Fq 'timed out' "$TMP/err" || fail "timeout message missing"

# Outside a git repository the worker warns but still runs.
(cd "$TMP/plain" && "$WORKER" "task") > /dev/null 2> "$TMP/err" || fail "non-git run failed"
grep -Fq 'not inside a git repository' "$TMP/err" || fail "non-git warning missing"

echo "PASS: worker behaves as expected."
