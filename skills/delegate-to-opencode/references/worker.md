# Worker reference

Details for `scripts/claude-opencode-worker` that the main flow in SKILL.md
does not need. Read only the section you need.

## Exit codes

- `0`: OpenCode finished, no permission was denied, and the check (if any)
  passed.
- `2`: usage error, not inside a git repository, or a requested model that
  OpenCode does not offer; nothing ran.
- `3`: OpenCode finished, but a permission was denied or auto-rejected; the
  report lists which. The task may be incomplete.
- `4`: a read-only run changed the working tree; review `Worker changes` and
  tell the user.
- `5`: a file changed inside `OPENCODE_WORKER_READ_DIRS`.
- `6`: the `OPENCODE_WORKER_CHECK` command failed; its output tail is in the
  report.
- `124`: OpenCode timed out; changes may be partial.

OpenCode itself exits 0 even after denied permissions; the worker turns those
into `3`.

## Report

The worker prints OpenCode's final answer (capped at 3000 characters, 12000
in read mode; `OPENCODE_WORKER_ANSWER_CHARS` changes it), a tool count, failed
and denied tool calls, OpenCode's token usage, the path of the full log, a
`Worker changes` section, and the `Session:` line.

`Worker changes` shows only what OpenCode changed, not changes that were
already in the working tree: a diffstat, a `git diff <baseline>` command, new
untracked files, and already-untracked files OpenCode changed (which
`git diff` does not show). When the whole diff, new files included, is at most
`OPENCODE_WORKER_DIFF_LINES` lines (default 60; `0` disables it), it is
printed inline.

The check in `OPENCODE_WORKER_CHECK` runs last, in the project directory, with
`OPENCODE_WORKER_CHECK_TIMEOUT` seconds (default 300). Files it creates are not
reported as OpenCode's changes. It does not run in read mode or after a
timeout.

Read the full log only for a specific question, with `grep` or `jq`, never
whole. `OPENCODE_WORKER_VERBOSE=1` also prints the transcript, for debugging
the worker itself.

## Fixing after review

Send only the correction to the same OpenCode session; it keeps the context of
its earlier work:

```bash
OPENCODE_WORKER_SESSION=ses_... OPENCODE_WORKER_CHECK='<same check>' bash <skill-base-dir>/scripts/claude-opencode-worker <<'TASK'
<only what must change, and why>
TASK
```

The resumed run keeps the session's model, and its report shows only that
round's changes. Small fixes are cheaper to make yourself.

## Read-only analysis

For questions about the code, run with `OPENCODE_WORKER_MODE=read`. OpenCode
uses its `plan` agent with file edits denied and bash limited to commands that
only read (`git log`, `git show`, `git diff`, `git blame`, `git grep`,
`git status`, `git ls-files`, `ls`, `cat`, `head`, `tail`, `grep`, `wc`,
`sort`, `uniq`). It answers with findings instead of a diff.

The answer is a lead, not a fact: open the files and lines it cites for every
point that matters before acting on it. Exit `3` in read mode often means
OpenCode tried a command outside the list and then answered another way; read
the answer before treating it as incomplete.

## Long tasks

Keep each task small enough to finish in a few minutes, and split larger work
into sequential delegations. The worker stops OpenCode after 570 s, below the
600 s maximum of the Bash tool. For a task that cannot be split, run it with
`run_in_background: true` and `OPENCODE_WORKER_TIMEOUT=1500`, and wait for the
completion notification.

## Files outside the repository

To let OpenCode read docs in a sibling repository or a runbook, pass their
directories in `OPENCODE_WORKER_READ_DIRS` (colon-separated absolute paths).
OpenCode may read them, never edit them; the worker exits `5` if anything
there changes. Without it, OpenCode cannot open them.

For a long task, write it once to a file in your scratchpad and pass it with
`< task.md`, so a run that fails before doing anything can be repeated without
writing the task again.

## What the worker blocks

OpenCode's own permission system denies, for delegated runs only: git commit,
push, reset, clean, checkout, switch, restore, stash, rebase and merge;
`rm -rf`; any file access outside the project directory, except OpenCode's own
scratch and truncated-output directories and `OPENCODE_WORKER_READ_DIRS`; and
every pattern in `~/.config/claude-opencode-worker/deny` (one shell glob per
line, e.g. `*supabase db reset*`). On OpenCode 2 the worker runs with
`--standalone`, because the shared background service would ignore these
rules.
