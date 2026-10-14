---
name: delegate-to-opencode
description: >
  Use proactively for straightforward, mechanical, repetitive, or well-defined
  coding tasks when the current main model is Opus. Delegate routine
  implementation, tests, simple refactors, repetitive edits, and file creation
  to OpenCode: e.g. writing tests for an existing route or function, adding a
  simple migration or column, applying the same change across several
  components, renaming, wiring an endpoint that follows an existing pattern.
  After OpenCode finishes, the main Opus session must review the resulting
  changes and tests before considering the delegated work complete. Do not use
  when the current model is Sonnet. Do not delegate architectural decisions,
  ambiguous requirements, security-sensitive work, or difficult debugging.
---

# Delegate to OpenCode

Use OpenCode as the implementation worker, while keeping the main Opus
session responsible for the final review and acceptance of the work.

## When to delegate

Do not delegate tasks involving:

- architectural decisions
- ambiguous requirements
- major design changes
- security-sensitive decisions
- difficult debugging requiring substantial reasoning
- changes where the correct implementation approach is unclear

Delegate when the implementation is straightforward, mechanical, repetitive,
or sufficiently well-defined that a separate coding worker can execute it
without making important design decisions.

## Writing the task

OpenCode starts cold. It reads the project's `CLAUDE.md`/`AGENTS.md`, but not
Claude Code's memory directory or this conversation. Write every task in this
shape:

```
Goal: <one or two sentences on what must exist when done>
Files: <files to change or create, and existing files to copy the pattern from>
Do not touch: <files, behaviour or APIs that must stay as they are>
Project rules: <any rule from memory or this conversation that applies,
  e.g. "use the existing logger, never console.log">
Done when: <observable result and the exact test/check command to run>
```

Keep each task small enough to finish in a few minutes. Split larger work into
several sequential delegations and review each one before sending the next.

## Delegation workflow

1. Preserve all relevant requirements from the user's request.
2. Write the task in the shape above.
3. Run the worker script that ships with this skill,
   `scripts/claude-opencode-worker` inside this skill's base directory, from
   the git repository that will be changed (not from a parent folder that
   holds several repositories; the worker refuses to run outside git). Call it
   through `bash` with its absolute path and pass the task on stdin through a
   quoted heredoc so `$`, backticks and quotes in the task are not expanded:

   ```bash
   bash <skill-base-dir>/scripts/claude-opencode-worker <<'TASK'
   <task>
   TASK
   ```

   Set the Bash tool timeout to 600000 ms. The worker stops OpenCode on its
   own after 570 s. For a task that genuinely cannot be split, run it with
   `run_in_background: true` and a longer limit, e.g.
   `OPENCODE_WORKER_TIMEOUT=1500 bash <skill-base-dir>/scripts/claude-opencode-worker <<'TASK'`,
   and wait for the completion notification.

   `OPENCODE_WORKER_MODEL=provider/model` pins the model; otherwise the
   worker prints which model OpenCode will probably use.

4. Wait for OpenCode to finish, then read the exit code:
   - `0`: finished with no denied permission.
   - `3`: finished, but a permission was denied or auto-rejected; the output
     lists which. The task may be incomplete.
   - `124`: timed out; changes may be partial.
   - `2`: usage error or not inside a git repository; nothing ran.
5. Treat OpenCode's output as an implementation attempt, not as final approval.
6. Inspect the diff yourself. The worker ends with a `Worker changes` section
   and a `git diff <baseline>` command that shows only what OpenCode changed,
   excluding changes that were already in the working tree. It also lists new
   untracked files, and files that were already untracked and that OpenCode
   changed, which `git diff` does not show.
7. Run the relevant tests, checks, linters, or other validation yourself when
   appropriate.
8. Review the implementation against the original requirements, including scope,
   correctness, regressions, and unintended changes.
9. Only after this review should you consider the delegated task complete.

The review in steps 6-8 should be performed by the main Claude Code session
(the Opus session that delegated the work), not silently delegated back to
OpenCode.

Do not blindly trust OpenCode's conclusions or its statement that tests pass.

## What the worker blocks

OpenCode's own permission system denies, for delegated runs only: git commit,
push, reset, clean, checkout, switch, restore, stash, rebase and merge;
`rm -rf`; any file access outside the project directory; and every extra
pattern the user listed in `~/.config/claude-opencode-worker/deny` (one shell
glob per line, e.g. `*supabase db reset*`). Do not ask OpenCode to do any of
these. If the task needs one of them, do that step yourself after reviewing.

Do not commit changes unless the user explicitly requested a commit.

Do not reset, clean, checkout, or discard existing user changes.

If the task is not appropriate for delegation, implement it directly.
