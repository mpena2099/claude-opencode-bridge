#!/usr/bin/env bash

# Runs one benchmark task in fresh `claude -p` Opus sessions, in parallel.
# Usage: bench/run.sh <task> <out-dir> [conditions...]
# Conditions (default: N F C):
#   N  Opus does it alone (prompt says not to delegate)
#   A  natural: skill available, nothing said
#   F  prompt asks for the delegate-to-opencode skill
#   C  prompt is sent through the /delegate command
# Append a digit to repeat a condition, e.g. N1 N2 C1 C2.
# Each session costs real Opus usage on the account running it.

set -euo pipefail

BENCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TASK="${1:?task name (directory under bench/tasks)}"
OUT="${2:?output directory}"
shift 2
CONDITIONS=("$@")
[[ ${#CONDITIONS[@]} -gt 0 ]] || CONDITIONS=(N F C)
TASK_DIR="$BENCH_DIR/tasks/$TASK"
[[ -f "$TASK_DIR/prompt.txt" ]] || { echo "unknown task: $TASK" >&2; exit 2; }

mkdir -p "$OUT"
for run in "${CONDITIONS[@]}"; do
    dir="$OUT/$run"
    if [[ -e "$dir" ]]; then
        echo "exists, skipping: $dir" >&2
        continue
    fi
    if [[ -x "$TASK_DIR/make_fixture.py" ]]; then
        mkdir -p "$dir"
        (cd "$dir" && "$TASK_DIR/make_fixture.py")
    else
        cp -a "$TASK_DIR/fixture" "$dir"
    fi
    git -C "$dir" init -q
    git -C "$dir" add -A
    git -C "$dir" -c user.email=bench@example.com -c user.name=bench commit -qm init

    prompt="$(cat "$TASK_DIR/prompt.txt")"
    case "${run:0:1}" in
        N) prompt+=$'\n\nDo it yourself; do not delegate to OpenCode.' ;;
        A) ;;
        F) prompt+=$'\n\nUse the delegate-to-opencode skill for this.' ;;
        C) prompt="/delegate $prompt" ;;
        *) echo "unknown condition: $run" >&2; exit 2 ;;
    esac
    printf '%s\n' "$prompt" > "$OUT/$run.prompt"

    (
        cd "$dir"
        start=$(date +%s)
        rc=0
        timeout 1500 claude -p --model opus --output-format stream-json --verbose \
            --allowedTools "Bash Skill Read Write Edit Glob Grep" \
            < "$OUT/$run.prompt" > "$OUT/$run.jsonl" 2> "$OUT/$run.err" || rc=$?
        echo "$run rc=$rc secs=$(( $(date +%s) - start ))" > "$OUT/$run.rc"
    ) &
done
wait
cat "$OUT"/*.rc
python3 "$BENCH_DIR/score.py" "$TASK" "$OUT"
