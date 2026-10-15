---
name: delegate-to-opencode
description: >
  Use proactively for straightforward, mechanical, repetitive, or well-defined
  coding tasks when the current main model is Opus. Delegate routine
  implementation, tests, simple refactors, repetitive edits, and file creation
  to OpenCode: e.g. writing tests for an existing route or function, adding a
  simple migration or column, applying the same change across several
  components, renaming, wiring an endpoint that follows an existing pattern.
  Also delegate read-only analysis that means reading many files: mapping
  every call site of a function, summarizing how a module works, finding the
  code that matches a pattern.
  After OpenCode finishes, the main Opus session must review the resulting
  changes and tests before considering the delegated work complete. Do not use
  when the current model is Sonnet. Do not delegate architectural decisions,
  ambiguous requirements, security-sensitive work, or difficult debugging.
license: MIT
compatibility: >-
  Built for Claude Code. Requires the opencode CLI, git and bash; python3 is
  used to report the model and find the OpenCode session, and the worker
  still runs without it.
metadata:
  version: 1.8.0
---

# Delegate to OpenCode

Use OpenCode as the implementation worker, while keeping the main Opus
session responsible for the final review and acceptance of the work.

The point is to make the Opus session cost less. Every token you write (the
task) and every token you read (the report, the diff, the files you open to
review) is paid at Opus prices; the tokens OpenCode spends are not. Delegating
only pays when OpenCode writes much more than you write and read to get it.

## Is it worth delegating?

Estimate before delegating, in your head, in one line:

- **Writing saved:** the code or answer OpenCode will produce.
- **Cost:** the task you will write, plus what you will have to read to
  accept the result (the diff, files to check, any rework).

Delegate only when the saving is clearly bigger, roughly 3x. Good fits:

- tests for existing code, accepted because they pass and cover the cases you
  listed;
- the same mechanical change across many files, accepted by the diff;
- new code that follows an existing file closely, where you name the file to
  copy instead of describing it;
- read-only analysis over many files, accepted by checking the few lines the
  answer cites.

Do it yourself when:

- the task text would be about as long as the code;
- you will need to read every line of the result anyway (code that touches
  production, money or security, interactive scripts, subtle logic);
- the change is small, or you already have the files in context.

When you skip delegation for a mechanical task, say why in one line.

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
Size: <a cap, e.g. "at most 150 lines"; OpenCode tends to write more>
Done when: <observable result and the exact test/check command to run>
```

Keep the task short; it is the part you pay for:

- Point at files instead of pasting them. OpenCode reads the project itself.
  For files outside the repository (docs in a sibling repo, a runbook), pass
  their directories in `OPENCODE_WORKER_READ_DIRS` (colon-separated absolute
  paths): OpenCode may read them, and the worker exits 5 if anything there
  changes. Without it, OpenCode cannot open them and guesses instead.
- Name the facts it cannot find (table columns, API shapes, exact strings),
  not the reasoning behind them.
- Write the task once to a file in your scratchpad and pass it with
  `< task.md`. If the run fails before doing anything (wrong path, missing
  tool), run it again from the file instead of writing the task again.

Keep each task small enough to finish in a few minutes. Split larger work into
several sequential delegations and review each one before sending the next.

## Choosing the model

Do not pass a model by default: OpenCode then uses its own default model,
which the user controls in OpenCode. Only when the user asks for a specific
model, pass it as `OPENCODE_WORKER_MODEL=provider/model` for the runs they
meant. Never choose a model on your own: most entries in `opencode models`
are billed per token. If the worker reports that the requested model is not
available, tell the user instead of picking a replacement.

## Read-only analysis

For questions about the code, not changes to it, run the worker with
`OPENCODE_WORKER_MODE=read`. OpenCode then runs its `plan` agent with file
edits denied and bash limited to commands that only read (`git log`,
`git show`, `git diff`, `git blame`, `git grep`, `git status`,
`git ls-files`, `ls`, `cat`, `head`, `tail`, `grep`, `wc`, `sort`, `uniq`).
It answers with findings instead of a diff:

```bash
OPENCODE_WORKER_MODE=read bash <skill-base-dir>/scripts/claude-opencode-worker <<'TASK'
Goal: <the question to answer>
Files: <where to look>
Done when: <what the answer must contain, e.g. every call site with file:line>
TASK
```

The answer is a lead, not a fact. Before you act on it or pass it to the
user, open the files and lines it cites for every point that matters. A
read-only run may end with exit 3 when OpenCode tried a command outside the
list and then answered another way; read the answer before treating it as
incomplete. Exit 4 means something changed the working tree anyway: review
the `Worker changes` section and tell the user.

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
   bash <skill-base-dir>/scripts/claude-opencode-worker < <scratchpad>/task.md
   ```

   A quoted heredoc (`<<'TASK' ... TASK`) also works for a short task.

   Set the Bash tool timeout to 600000 ms. The worker stops OpenCode on its
   own after 570 s. For a task that genuinely cannot be split, run it with
   `run_in_background: true` and a longer limit, e.g.
   `OPENCODE_WORKER_TIMEOUT=1500 bash <skill-base-dir>/scripts/claude-opencode-worker <<'TASK'`,
   and wait for the completion notification.

   Choose the model as described in "Choosing the model" below.

4. Wait for OpenCode to finish, then read the exit code:
   - `0`: finished with no denied permission.
   - `3`: finished, but a permission was denied or auto-rejected; the output
     lists which. The task may be incomplete.
   - `124`: timed out; changes may be partial.
   - `2`: usage error, not inside a git repository, or a requested model that
     OpenCode does not offer; nothing ran.
   - `4`: a read-only run changed the working tree.
   - `5`: a file changed inside `OPENCODE_WORKER_READ_DIRS`.

   The worker prints a short report, not OpenCode's transcript: OpenCode's
   final answer (capped at 3000 characters, 12000 in read mode;
   `OPENCODE_WORKER_ANSWER_CHARS` changes it), a tool count, failed and
   denied tool calls, OpenCode's token usage and the path of the full log.
   Read the log only for a specific question, with `grep` or `jq` on it,
   never whole. `OPENCODE_WORKER_VERBOSE=1` prints the transcript too, for
   debugging the worker itself.
5. Treat OpenCode's output as an implementation attempt, not as final approval.
6. Inspect the diff yourself, as cheaply as the risk allows. The worker ends
   with a `Worker changes` section and a `git diff <baseline>` command that
   shows only what OpenCode changed, excluding changes that were already in
   the working tree. It also lists new untracked files, and files that were
   already untracked and that OpenCode changed, which `git diff` does not
   show. Start from the diffstat and the tests: read the hunks that carry
   logic, skim the rest, and open a whole new file only when it is short or
   nothing else can check it. Search the result for the risky patterns in the
   checklist instead of reading it line by line.
7. Run the relevant tests, checks, linters, or other validation yourself when
   appropriate; a passing test you can trust is cheaper than reading code.
8. Review the implementation against the original requirements, including scope,
   correctness, regressions, and unintended changes, following
   [references/review-checklist.md](references/review-checklist.md): weakened
   tests, hardcoded success, swallowed errors, nonexistent APIs, dead code.
9. Only after this review should you consider the delegated task complete.

The review in steps 6-8 should be performed by the main Claude Code session
(the Opus session that delegated the work), not silently delegated back to
OpenCode.

Do not blindly trust OpenCode's conclusions or its statement that tests pass.

## Fixing after review

The worker ends with a `Session:` line. When the review finds something
OpenCode should fix, send only the correction to that same session instead of
restating the whole task; OpenCode keeps the context of its earlier work:

```bash
OPENCODE_WORKER_SESSION=ses_... bash <skill-base-dir>/scripts/claude-opencode-worker <<'TASK'
<only what must change, and why>
TASK
```

The resumed run keeps the session's model. Its `Worker changes` section shows
only the changes from this round, so review it the same way. Small fixes are
often faster to make yourself; resume when the correction is mechanical and
spread across the files OpenCode already touched.

## What the worker blocks

OpenCode's own permission system denies, for delegated runs only: git commit,
push, reset, clean, checkout, switch, restore, stash, rebase and merge;
`rm -rf`; any file access outside the project directory, except OpenCode's
own scratch and truncated-output directories and the directories in
`OPENCODE_WORKER_READ_DIRS`; and every extra
pattern the user listed in `~/.config/claude-opencode-worker/deny` (one shell
glob per line, e.g. `*supabase db reset*`). Do not ask OpenCode to do any of
these. If the task needs one of them, do that step yourself after reviewing.

Do not commit changes unless the user explicitly requested a commit.

Do not reset, clean, checkout, or discard existing user changes.

If the task is not appropriate for delegation, implement it directly.
