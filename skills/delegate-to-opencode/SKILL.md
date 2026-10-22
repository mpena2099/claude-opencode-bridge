---
name: delegate-to-opencode
description: >
  Use when the current main model is Opus and you are about to write a large
  amount of straightforward code yourself: a test suite for existing code,
  boilerplate that follows an existing file, new code across many files, or
  read-only analysis that means reading many files. OpenCode
  writes it on a free model and you review the result, which costs far fewer
  Opus tokens than writing it. After OpenCode finishes, the main Opus session
  must review the resulting changes before considering the work complete. Do
  not use when the current model is Sonnet. Do not delegate small edits,
  architectural decisions, ambiguous requirements, security-sensitive work, or
  difficult debugging.
license: MIT
compatibility: >-
  Built for Claude Code. Requires the opencode CLI, git and bash; python3 is
  used to summarize OpenCode's output, and the worker still runs without it.
metadata:
  version: 1.13.0
---

# Delegate to OpenCode

The point is to spend fewer Opus tokens. You pay for what you write and for
every turn, because each turn re-reads your whole context. Delegating pays
only when OpenCode writes much more than the delegation costs you:

- **Worth it:** you would otherwise write a lot of new code yourself (roughly
  150+ lines), and a command can check it (tests pass, build succeeds) or a
  skim of the diff can. A delegated test suite costs about 30% fewer Opus
  tokens than writing it, but tends to be smaller unless `Done when` names
  the cases that matter.
- **Also worth it: investigation with long output.** Counting rows, joining
  catalogs, probing an API, grepping logs or tracing where something is used:
  if you would read pages of output to get a one-line answer, delegate it and
  ask only for the conclusion and the numbers. Every line of output you read
  yourself is re-read on every later turn. Questions about the code alone go
  in read mode; anything that must run a script goes in edit mode, with the
  script in a scratch folder inside the project and `Done when` naming the
  numbers to report.
- **Also worth it: a second opinion.** After a large change of your own, a
  read-mode run can critique the diff or plan and return a short list of
  suspected bugs (see references/worker.md).
- **Batch small tasks.** Two or three independent tasks that are each too
  small to delegate alone can share one run: list them as numbered goals in
  one `TASK`, with one check that covers all of them.
- **Not worth it either:** a change you can make with a short script or a
  `sed` over many files. Writing the script costs less than the delegation.
- **Not worth it:** small changes, code you will read line by line anyway
  (money, auth, security, production data), or files you already have in
  context and could just edit.
- **Never delegate:** architecture, ambiguous requirements, design decisions,
  difficult debugging. Do those yourself.

When you skip delegation for a mechanical task, say why in one line.

## The flow: one worker call, then answer

Aim for exactly one Bash call after loading this skill. Each extra turn costs
roughly as much as writing a few hundred tokens of code.

1. **Do not read the code first.** OpenCode reads the project itself. Name the
   files; read something only if you need a fact for the task that you do not
   already have.
2. **Run the worker once**, from the git repository to change, with the check
   command in `OPENCODE_WORKER_CHECK` and the Bash tool timeout at 600000 ms:

   ```bash
   OPENCODE_WORKER_CHECK='<test or build command>' bash <skill-base-dir>/scripts/claude-opencode-worker <<'TASK'
   Goal: <what must exist when done>
   Files: <files to change or create; existing files to copy the pattern from>
   Do not touch: <files or behaviour that must stay as they are>
   Rules: <project rules from memory or this conversation that apply>
   Size: <a cap, e.g. "at most 300 lines">
   Done when: <observable result; for tests, the cases each function must
     cover: boundaries, empty input, every error path>
   Stop if: <when to stop and report instead of forcing it, e.g. "the check
     can only pass by changing a file in Do not touch">
   TASK
   ```

   Pair every hard rule with a `Stop if`. Without one, a worker that cannot
   meet a rule tends to game it (weakens the test, skips the case); with one,
   it stops and says why, which counts as a good run.

   Keep the task short: point at files instead of pasting them, and name only
   facts OpenCode cannot find (columns, API shapes, exact strings). OpenCode
   reads the project's `CLAUDE.md`/`AGENTS.md`, not your memory or this
   conversation.

3. **Review from the report.** The worker prints OpenCode's answer, the
   diffstat, the diff itself when it is short (60 lines or less), and the
   result of your check, which it runs after OpenCode finishes. Exit code `0`
   means OpenCode finished and the check passed; anything else, see
   [references/worker.md](references/worker.md).
   - Check passed and the diff is printed: skim it for the patterns in
     [references/review-checklist.md](references/review-checklist.md) and
     answer. No further reads are needed.
   - Diff not printed: if the check passed and the task was tests or
     boilerplate, the diffstat is enough. Otherwise run one targeted read
     (`git diff <baseline> -- <file>` on the files that carry logic, or `grep`
     for risky patterns), not a full read of every file.
   - Something is wrong: fix it yourself if small; otherwise resume the same
     OpenCode session with only the correction (see references/worker.md).
     After two correction rounds that still fail, finish it yourself.

Do not trust OpenCode's claims; trust the check output and the diff. The
review is yours, not OpenCode's.

## Model

Do not pass a model. OpenCode uses its own default, which the user controls.
Only when the user asks for a specific model, set
`OPENCODE_WORKER_MODEL=provider/model`. If the worker says it is unavailable,
tell the user instead of picking another.

## Limits

The worker blocks, for delegated runs only: destructive git commands (commit,
push, reset, clean, checkout, switch, restore, stash, rebase, merge),
`rm -rf`, file access outside the project, and the user's extra deny
patterns. Do not ask OpenCode to do any of these; do that step yourself after
reviewing. Before you edit or commit, check that no worker is still running
(`pgrep -fa claude-opencode-worker`), for example one started in the
background; wait for it or stop it first. Do not commit unless the user asked. Do not reset, clean, checkout,
or discard existing user changes.

For read-only questions, long tasks, sharing files outside the repository, and
exit codes, see [references/worker.md](references/worker.md).
