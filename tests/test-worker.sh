#!/usr/bin/env bash

# Exercises skills/delegate-to-opencode/scripts/claude-opencode-worker against
# a stub `opencode`, so it runs without OpenCode installed and without calling
# any model.

set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORKER="$REPO_DIR/skills/delegate-to-opencode/scripts/claude-opencode-worker"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/out" "$TMP/repo" "$TMP/plain"
git -C "$TMP/repo" init -q
echo init > "$TMP/repo/init.txt"
git -C "$TMP/repo" add init.txt
(cd "$TMP/repo" && git -c user.email=t@t -c user.name=t commit -qm init)

cat > "$TMP/bin/opencode" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
    echo "0.0.0-stub"
    exit 0
fi
printf '%s\n' "$@" > "$STUB_OUT/args"
printf '%s' "${OPENCODE_CONFIG_CONTENT:-}" > "$STUB_OUT/config"
if [[ -n "${STUB_PRINT:-}" ]]; then
    echo "$STUB_PRINT"
fi
if [[ -n "${STUB_ACTION:-}" ]]; then
    bash -c "$STUB_ACTION"
fi
if [[ -n "${STUB_SLEEP:-}" ]]; then
    sleep "$STUB_SLEEP"
fi
exit "${STUB_EXIT:-0}"
STUB
chmod +x "$TMP/bin/opencode"

export PATH="$TMP/bin:$PATH"
export STUB_OUT="$TMP/out"
export OPENCODE_WORKER_DENY_FILE="$TMP/no-deny-file"
unset OPENCODE_CONFIG_CONTENT OPENCODE_WORKER_MODEL OPENCODE_WORKER_TIMEOUT
unset STUB_PRINT STUB_ACTION STUB_EXIT STUB_SLEEP

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

# Outside a git repository the worker refuses with exit 2.
rc=0; (cd "$TMP/plain" && "$WORKER" "task") > /dev/null 2> "$TMP/err" || rc=$?
[[ $rc -eq 2 ]] || fail "non-git should exit 2, got $rc"
grep -Fq 'not inside a git repository' "$TMP/err" || fail "non-git warning missing"

# Extra deny file patterns reach OpenCode as JSON deny rules.
cat > "$TMP/deny" <<'EOF'
# ignore-me-comment-xyz

*supabase db reset*
*say "hi"*
EOF
OPENCODE_WORKER_DENY_FILE="$TMP/deny" run_worker "task" > /dev/null || fail "deny file run failed"
python3 -m json.tool "$TMP/out/config" > /dev/null || fail "deny config is not valid JSON"
grep -Fq '"*supabase db reset*": "deny"' "$TMP/out/config" || fail "deny file pattern missing"
grep -Fq '"*say \"hi\"*": "deny"' "$TMP/out/config" || fail "deny file quote pattern missing"
grep -Fq '"external_directory": "deny"' "$TMP/out/config" || fail "external_directory deny missing"
if grep -Fq 'ignore-me-comment-xyz' "$TMP/out/config"; then
    fail "deny file comment leaked into config"
fi

# Auto-rejected permissions are reported with exit 3.
rc=0; STUB_PRINT='permission requested: bash; auto-rejecting' run_worker "task" > /dev/null 2> "$TMP/err" || rc=$?
[[ $rc -eq 3 ]] || fail "auto-reject should exit 3, got $rc"
grep -Fq 'denied or auto-rejected' "$TMP/err" || fail "auto-reject message missing"

# Deny-rule hits are reported with exit 3.
rc=0; STUB_PRINT='Error: The user has specified a rule which prevents you from using this specific tool call.' run_worker "task" > /dev/null 2> "$TMP/err" || rc=$?
[[ $rc -eq 3 ]] || fail "deny hit should exit 3, got $rc"

# Baseline diff excludes pre-existing changes.
echo base > "$TMP/repo/pre.txt"
echo base > "$TMP/repo/work.txt"
git -C "$TMP/repo" add pre.txt work.txt
(cd "$TMP/repo" && git -c user.email=t@t -c user.name=t commit -qm "add pre and work")
echo modified > "$TMP/repo/pre.txt"
STUB_ACTION='echo worker >> work.txt; echo new > newfile.txt' run_worker "task" > "$TMP/out-report" 2> "$TMP/err-report" || fail "baseline run failed"
grep -Fq 'Pre-existing changes' "$TMP/out-report" || fail "pre-existing header missing"
grep -Fq 'work.txt' "$TMP/out-report" || fail "worker-changed file missing from report"
grep -Fq 'newfile.txt' "$TMP/out-report" || fail "new untracked file missing from report"
DIFFSTAT="$(sed -n '/=== Worker changes ===/,/Review with:/p' "$TMP/out-report")"
if grep -Fq 'pre.txt' <<< "$DIFFSTAT"; then
    fail "diffstat should not list pre-existing pre.txt"
fi
if ! grep -Fq 'work.txt' <<< "$DIFFSTAT"; then
    fail "diffstat should list worker-changed work.txt"
fi
git -C "$TMP/repo" checkout -- pre.txt work.txt
rm -f "$TMP/repo/newfile.txt"

# Edits to already-untracked files are reported separately.
echo before > "$TMP/repo/old-untracked.txt"
STUB_ACTION='echo after >> old-untracked.txt' run_worker "task" > "$TMP/out-untracked" 2> "$TMP/err-untracked" || fail "untracked run failed"
grep -Fq 'Already-untracked files the worker changed' "$TMP/out-untracked" || fail "untracked header missing"
grep -Fq 'old-untracked.txt' "$TMP/out-untracked" || fail "untracked file missing from report"

echo "PASS: worker behaves as expected."
