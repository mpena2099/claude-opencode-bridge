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
    echo "${STUB_VERSION:-0.0.0-stub}"
    exit 0
fi
if [[ "${1:-}" == "models" ]]; then
    printf '%s\n' "${STUB_MODELS:-provider/model}"
    exit "${STUB_MODELS_EXIT:-0}"
fi
if [[ "${1:-}" == "session" ]]; then
    printf '%s\n' "$@" > "$STUB_OUT/session-args"
    if [[ -z "${STUB_SESSIONS+x}" && -f "$STUB_OUT/title" ]]; then
        printf '[{"id":"ses_TEST123","title":"%s"}]' "$(cat "$STUB_OUT/title")"
        exit 0
    fi
    printf '%s' "${STUB_SESSIONS:-[]}"
    exit 0
fi
prev=""
for arg in "$@"; do
    if [[ "$prev" == "--title" ]]; then
        printf '%s' "$arg" > "$STUB_OUT/title"
        break
    fi
    prev="$arg"
done
printf '%s\n' "$@" > "$STUB_OUT/args"
pwd > "$STUB_OUT/cwd"
printf '%s' "${OPENCODE_CONFIG_CONTENT:-}" > "$STUB_OUT/config"
if [[ -n "${STUB_PRINT:-}" ]]; then
    echo "$STUB_PRINT"
fi
if [[ -n "${STUB_EVENTS:-}" ]]; then
    cat "$STUB_EVENTS"
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
export OPENCODE_WORKER_LOG_DIR="$TMP/logs"
unset OPENCODE_CONFIG_CONTENT OPENCODE_WORKER_MODEL OPENCODE_WORKER_TIMEOUT
unset STUB_PRINT STUB_ACTION STUB_EXIT STUB_SLEEP STUB_EVENTS OPENCODE_WORKER_READ_DIRS OPENCODE_WORKER_VERBOSE

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
if grep -Fxq -- '--standalone' "$TMP/out/args"; then
    fail "OpenCode 1 should not get --standalone"
fi

# OpenCode 2: --standalone so the deny config applies, no --dir, run from the project.
STUB_VERSION='opencode v2.0.31' run_worker "task" > /dev/null || fail "OpenCode 2 run failed"
grep -Fxq -- '--standalone' "$TMP/out/args" || fail "OpenCode 2 should get --standalone"
if grep -Fxq -- '--dir' "$TMP/out/args"; then
    fail "OpenCode 2 should not get --dir"
fi
[[ "$(cat "$TMP/out/cwd")" == "$TMP/repo" ]] || fail "OpenCode 2 should run from the project directory"

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
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["permission"]["external_directory"]["*"] == "deny"' "$TMP/out/config" || fail "external_directory deny missing"
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

# The deny message quoted inside file content (e.g. a printed diff) is not a hit.
rc=0; STUB_PRINT="+  STUB_PRINT='Error: The user has specified a rule which prevents you from using this specific tool call.'" run_worker "task" > /dev/null 2>&1 || rc=$?
[[ $rc -eq 0 ]] || fail "quoted deny message should not exit 3, got $rc"

# Default run uses the build agent.
run_worker "task" > /dev/null || fail "default agent run failed"
AGENT_ARG="$(awk '/^--agent$/{getline; print}' "$TMP/out/args")"
[[ "$AGENT_ARG" == "build" ]] || fail "default agent should be build, got $AGENT_ARG"

# Read-only mode uses the plan agent, a deny-all config and a read-only prompt.
OPENCODE_WORKER_MODE='read' run_worker "task" > "$TMP/out-read" 2> "$TMP/err-read" || fail "read mode run failed"
READ_AGENT="$(awk '/^--agent$/{getline; print}' "$TMP/out/args")"
[[ "$READ_AGENT" == "plan" ]] || fail "read mode agent should be plan, got $READ_AGENT"
python3 -m json.tool "$TMP/out/config" > /dev/null || fail "read config is not valid JSON"
grep -Fq '"edit": "deny"' "$TMP/out/config" || fail "read edit deny missing"
grep -Fq '"*": "deny"' "$TMP/out/config" || fail "read bash deny-all missing"
grep -Fq '"git log *": "allow"' "$TMP/out/config" || fail "read git log allow missing"
grep -Fq '"rtk git log *": "allow"' "$TMP/out/config" || fail "read rtk git log allow missing"
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["permission"]["external_directory"]["*"] == "deny"' "$TMP/out/config" || fail "read external_directory deny missing"
grep -Fq 'read-only analysis worker' "$TMP/out/args" || fail "read-only prompt missing"
grep -Fq 'Mode: read' "$TMP/out-read" || fail "read mode label missing"

# Read-only mode ignores the extra deny file.
OPENCODE_WORKER_MODE='read' OPENCODE_WORKER_DENY_FILE="$TMP/deny" run_worker "task" > /dev/null || fail "read deny file run failed"
if grep -Fq '*supabase db reset*' "$TMP/out/config"; then
    fail "read mode should ignore deny file"
fi

# Read-only mode fails when the run creates a new file.
rc=0; OPENCODE_WORKER_MODE='read' STUB_ACTION='echo x > read-only-new.txt' run_worker "task" > /dev/null 2> "$TMP/err-read-new" || rc=$?
[[ $rc -eq 4 ]] || fail "read-only new file should exit 4, got $rc"
grep -Fq 'read-only run changed the working tree' "$TMP/err-read-new" || fail "read-only new file message missing"
rm -f "$TMP/repo/read-only-new.txt"

# Read-only mode fails when the run modifies a tracked file.
rc=0; OPENCODE_WORKER_MODE='read' STUB_ACTION='echo changed > init.txt' run_worker "task" > /dev/null 2> "$TMP/err-read-modify" || rc=$?
[[ $rc -eq 4 ]] || fail "read-only modify should exit 4, got $rc"
echo init > "$TMP/repo/init.txt"

# Unknown modes are usage errors.
rc=0; OPENCODE_WORKER_MODE='bogus' run_worker "task" > /dev/null 2> "$TMP/err-bogus" || rc=$?
[[ $rc -eq 2 ]] || fail "bogus mode should exit 2, got $rc"
grep -Fq 'OPENCODE_WORKER_MODE must be' "$TMP/err-bogus" || fail "bogus mode message missing"

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

# New run passes a unique --title and no --session.
rm -f "$TMP/out/title"
STUB_SESSIONS='[]' run_worker "task" > "$TMP/out-new" || fail "new run failed"
grep -Fxq -- '--title' "$TMP/out/args" || fail "--title missing on new run"
TITLE="$(awk '/^--title$/{getline; print}' "$TMP/out/args")"
[[ "$TITLE" == claude-opencode-worker\ * ]] || fail "unexpected --title value: $TITLE"
if grep -Fxq -- '--session' "$TMP/out/args"; then
    fail "new run should not pass --session"
fi
rm -f "$TMP/out/title"

# Session discovery finds the new session by title.
rm -f "$TMP/out/title"
unset STUB_SESSIONS
run_worker "task" > "$TMP/out-session" || fail "session discovery run failed"
grep -Fq 'Session: ses_TEST123' "$TMP/out-session" || fail "session id missing from report"
grep -Fq 'OPENCODE_WORKER_SESSION=ses_TEST123' "$TMP/out-session" || fail "session resume hint missing"
rm -f "$TMP/out/title"

# Resume passes --session and a follow-up prompt, without --title.
rm -f "$TMP/out/title" "$TMP/out/args"
STUB_SESSIONS='[]' OPENCODE_WORKER_SESSION=ses_ABC run_worker "task" > "$TMP/out-resume" || fail "resume run failed"
grep -Fxq -- '--session' "$TMP/out/args" || fail "--session missing on resume"
RESUME_SESSION="$(awk '/^--session$/{getline; print}' "$TMP/out/args")"
[[ "$RESUME_SESSION" == "ses_ABC" ]] || fail "unexpected --session value: $RESUME_SESSION"
if grep -Fxq -- '--title' "$TMP/out/args"; then
    fail "resume should not pass --title"
fi
grep -Fq 'Follow-up on the task you already worked on' "$TMP/out/args" || fail "follow-up prompt missing"
grep -Fq 'Resuming session: ses_ABC' "$TMP/out-resume" || fail "resuming header missing"
rm -f "$TMP/out/title"

# Invalid session ids are rejected before calling OpenCode.
rm -f "$TMP/out/title" "$TMP/out/args"
rc=0; OPENCODE_WORKER_SESSION='bad; rm' run_worker "task" > /dev/null 2> "$TMP/err-invalid" || rc=$?
[[ $rc -eq 2 ]] || fail "invalid session id should exit 2, got $rc"
grep -Fq 'must be an OpenCode session id' "$TMP/err-invalid" || fail "invalid session message missing"
[[ ! -e "$TMP/out/args" ]] || fail "opencode should not run on invalid session id"
rm -f "$TMP/out/title"

# Without OPENCODE_WORKER_MODEL, no --model is passed and the default is reported.
run_worker "task" > "$TMP/out-default-model" || fail "default model run failed"
if grep -Fxq -- '--model' "$TMP/out/args"; then
    fail "default run should not pass --model"
fi
grep -Fq 'OpenCode default' "$TMP/out-default-model" || fail "default model label missing"

# Explicit OPENCODE_WORKER_MODEL that OpenCode offers is passed through.
STUB_MODELS=$'a/first\nb/second' OPENCODE_WORKER_MODEL=b/second run_worker "task" > /dev/null || fail "explicit model run failed"
MODEL_ARG="$(awk '/^--model$/{getline; print}' "$TMP/out/args")"
[[ "$MODEL_ARG" == "b/second" ]] || fail "explicit model should be b/second, got $MODEL_ARG"

# A model missing from `opencode models` is rejected before calling OpenCode.
rm -f "$TMP/out/args"
rc=0; STUB_MODELS='z/else' OPENCODE_WORKER_MODEL=a/first run_worker "task" > /dev/null 2> "$TMP/err-models-unavailable" || rc=$?
[[ $rc -eq 2 ]] || fail "unavailable model should exit 2, got $rc"
grep -Fq 'is not available in OpenCode' "$TMP/err-models-unavailable" || fail "unavailable model message missing"
[[ ! -e "$TMP/out/args" ]] || fail "opencode should not run on unavailable model"

# When `opencode models` fails, the run proceeds with the requested model.
rm -f "$TMP/out/args"
STUB_MODELS_EXIT=1 OPENCODE_WORKER_MODEL=a/first run_worker "task" > /dev/null 2> "$TMP/err-models-list-fails" || fail "model listing failure run failed"
grep -Fq 'could not list OpenCode models' "$TMP/err-models-list-fails" || fail "model listing warning missing"
MODEL_ARG="$(awk '/^--model$/{getline; print}' "$TMP/out/args")"
[[ "$MODEL_ARG" == "a/first" ]] || fail "model should be a/first when listing fails, got $MODEL_ARG"

# Resume without an explicit model keeps the session's model.
STUB_SESSIONS='[]' OPENCODE_WORKER_SESSION=ses_ABC run_worker "task" > "$TMP/out-models-resume" || fail "resume model run failed"
if grep -Fxq -- '--model' "$TMP/out/args"; then
    fail "resume should not pass --model"
fi
grep -Fq "resumed session's model" "$TMP/out-models-resume" || fail "resume model label missing"

# JSON events: only the final answer reaches stdout, with tools and tokens;
# the transcript stays in the log file.
cat > "$TMP/events.jsonl" <<'EOF'
{"type":"step_start","sessionID":"ses_JSON42","part":{"type":"step-start"}}
{"type":"text","sessionID":"ses_JSON42","part":{"type":"text","text":"INTERMEDIATE-NARRATION"}}
{"type":"tool_use","sessionID":"ses_JSON42","part":{"type":"tool","tool":"read","state":{"status":"completed","input":{"filePath":"/x/a.ts"},"output":"Error: The user has specified a rule which prevents you QUOTED-IN-FILE"}}}
{"type":"tool_use","sessionID":"ses_JSON42","part":{"type":"tool","tool":"bash","state":{"status":"error","input":{"command":"npm test"},"error":"exit 1: tests failed"}}}
{"type":"step_finish","sessionID":"ses_JSON42","part":{"type":"step-finish","tokens":{"input":100,"output":20,"cache":{"read":300}}}}
{"type":"text","sessionID":"ses_JSON42","part":{"type":"text","text":"FINAL-ANSWER: changed a.ts"}}
{"type":"step_finish","sessionID":"ses_JSON42","part":{"type":"step-finish","tokens":{"input":5,"output":7,"cache":{"read":1}}}}
EOF
rc=0; STUB_SESSIONS='[]' STUB_EVENTS="$TMP/events.jsonl" run_worker "task" > "$TMP/out-json" 2> "$TMP/err-json" || rc=$?
[[ $rc -eq 0 ]] || fail "json run should exit 0 (quoted deny text in tool output is not a hit), got $rc"
grep -Fxq -- '--format' "$TMP/out/args" || fail "--format json missing"
grep -Fq 'FINAL-ANSWER: changed a.ts' "$TMP/out-json" || fail "final answer missing"
if grep -Fq 'INTERMEDIATE-NARRATION' "$TMP/out-json"; then
    fail "intermediate text should stay out of stdout"
fi
grep -Fq 'Tools: bash x1, read x1' "$TMP/out-json" || fail "tool count missing"
grep -Fq 'bash npm test: exit 1: tests failed' "$TMP/out-json" || fail "failed tool call missing"
grep -Fq 'OpenCode tokens: input 105, output 27, cache read 301' "$TMP/out-json" || fail "token usage missing"
grep -Fq 'Session: ses_JSON42' "$TMP/out-json" || fail "session id from events missing"
LOGFILE="$(sed -n 's/^Full log: //p' "$TMP/out-json")"
grep -Fq 'INTERMEDIATE-NARRATION' "$LOGFILE" || fail "full log should keep the transcript"

# Verbose mode prints the transcript too.
STUB_SESSIONS='[]' STUB_EVENTS="$TMP/events.jsonl" OPENCODE_WORKER_VERBOSE=1 run_worker "task" > "$TMP/out-verbose" || fail "verbose run failed"
grep -Fq 'INTERMEDIATE-NARRATION' "$TMP/out-verbose" || fail "verbose transcript missing"

# The final answer is capped.
STUB_SESSIONS='[]' STUB_EVENTS="$TMP/events.jsonl" OPENCODE_WORKER_ANSWER_CHARS=5 run_worker "task" > "$TMP/out-cap" || fail "capped run failed"
grep -Fq 'answer cut at 5 characters' "$TMP/out-cap" || fail "answer cap note missing"

# A denied tool call inside the JSON events exits 3.
cat > "$TMP/events-denied.jsonl" <<'EOF'
{"type":"tool_use","sessionID":"ses_D","part":{"type":"tool","tool":"read","state":{"status":"error","input":{"filePath":"/outside/doc.md"},"error":"The user has specified a rule which prevents you from using this specific tool call."}}}
{"type":"text","sessionID":"ses_D","part":{"type":"text","text":"done anyway"}}
EOF
rc=0; STUB_SESSIONS='[]' STUB_EVENTS="$TMP/events-denied.jsonl" run_worker "task" > /dev/null 2> "$TMP/err-denied" || rc=$?
[[ $rc -eq 3 ]] || fail "denied tool call in events should exit 3, got $rc"
grep -Fq '/outside/doc.md' "$TMP/err-denied" || fail "denied tool target missing"

# OpenCode 2 wording for deny hits and auto-rejects also exits 3.
for err in 'Permission denied: shell' 'This non-interactive run cannot ask the user for permission, so the request was rejected.'; do
    printf '{"type":"tool_use","sessionID":"ses_D","part":{"type":"tool","tool":"shell","state":{"status":"error","input":{"command":"touch x"},"error":"%s"}}}\n' "$err" > "$TMP/events-denied2.jsonl"
    rc=0; STUB_SESSIONS='[]' STUB_EVENTS="$TMP/events-denied2.jsonl" run_worker "task" > /dev/null 2>&1 || rc=$?
    [[ $rc -eq 3 ]] || fail "OpenCode 2 error '$err' should exit 3, got $rc"
done

# Read dirs: allowed in the config, named in the prompt, and edits there exit 5.
mkdir -p "$TMP/docs"
echo doc > "$TMP/docs/ref.md"
OPENCODE_WORKER_READ_DIRS="$TMP/docs" run_worker "task" > /dev/null || fail "read dirs run failed"
python3 -c 'import json,sys; c=json.load(open(sys.argv[1]))["permission"]["external_directory"]; assert c[sys.argv[2] + "/*"] == "allow" and c["*"] == "deny"' "$TMP/out/config" "$TMP/docs" || fail "read dir allow rule missing"
grep -Fq "never edit, these directories outside the project: $TMP/docs" "$TMP/out/args" || fail "read dirs prompt note missing"
rc=0; OPENCODE_WORKER_READ_DIRS="$TMP/docs" STUB_ACTION="sleep 1; echo changed > '$TMP/docs/ref.md'" run_worker "task" > /dev/null 2> "$TMP/err-readdir" || rc=$?
[[ $rc -eq 5 ]] || fail "edit in read dir should exit 5, got $rc"
grep -Fq 'ref.md' "$TMP/err-readdir" || fail "changed read-dir file missing from error"
rc=0; OPENCODE_WORKER_READ_DIRS="relative/path" run_worker "task" > /dev/null 2>&1 || rc=$?
[[ $rc -eq 2 ]] || fail "relative read dir should exit 2, got $rc"

# A small diff is printed inline, including new files; a large one is not.
rc=0; STUB_ACTION='printf "one\ntwo\n" > inline-new.txt' run_worker "task" > "$TMP/out-diff" 2>&1 || rc=$?
grep -Fq -- '--- Diff (' "$TMP/out-diff" || fail "small diff should be printed"
grep -Fq '+two' "$TMP/out-diff" || fail "new file content missing from inline diff"
rm -f "$TMP/repo/inline-new.txt"
OPENCODE_WORKER_DIFF_LINES=3 STUB_ACTION='seq 1 50 > inline-big.txt' run_worker "task" > "$TMP/out-diff" 2>&1 || true
grep -Fq 'over OPENCODE_WORKER_DIFF_LINES=3; not printed' "$TMP/out-diff" || fail "large diff should not be printed"
if grep -Fq -- '--- Diff (' "$TMP/out-diff"; then fail "large diff was printed"; fi
rm -f "$TMP/repo/inline-big.txt"

# The check command runs after the run; a failure exits 6 and its artifacts are not reported as changes.
OPENCODE_WORKER_CHECK='echo all-good; touch check-artifact.txt' run_worker "task" > "$TMP/out-check" 2>&1 || fail "passing check run failed"
grep -Fq '=== Check passed' "$TMP/out-check" || fail "check pass banner missing"
grep -Fq 'all-good' "$TMP/out-check" || fail "check output missing"
if grep -Fq '  check-artifact.txt' "$TMP/out-check"; then fail "check artifact reported as worker change"; fi
rm -f "$TMP/repo/check-artifact.txt"
rc=0; OPENCODE_WORKER_CHECK='echo broken; exit 1' run_worker "task" > "$TMP/out-check" 2>&1 || rc=$?
[[ $rc -eq 6 ]] || fail "failing check should exit 6, got $rc"
grep -Fq 'Check FAILED (exit 1)' "$TMP/out-check" || fail "check failure banner missing"
rc=0; OPENCODE_WORKER_MODE=read OPENCODE_WORKER_CHECK='exit 1' run_worker "task" > /dev/null 2>&1 || rc=$?
[[ $rc -eq 0 ]] || fail "read mode should ignore the check, got $rc"

echo "PASS: worker behaves as expected."
