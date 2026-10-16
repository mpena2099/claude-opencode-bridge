---
description: Delegate a coding task to OpenCode and review the result (saves Opus tokens)
argument-hint: <task>
---

Delegate this task to OpenCode with one worker call, then review and answer:

$ARGUMENTS

1. Do not read the code first; OpenCode reads the project. Name files instead.
2. Run once, from the git repository to change, Bash timeout 600000 ms:

   ```bash
   OPENCODE_WORKER_CHECK='<test or build command>' bash ~/.claude/skills/delegate-to-opencode/scripts/claude-opencode-worker <<'TASK'
   Goal: <what must exist when done>
   Files: <files to change or create; files to copy the pattern from>
   Do not touch: <what must stay as it is>
   Rules: <project rules from memory or this conversation>
   Size: <cap, e.g. "at most 300 lines">
   Done when: <observable result; for tests, the cases each function must cover: boundaries, empty input, every error path>
   TASK
   ```

   Do not pass a model unless the user asked for one (`OPENCODE_WORKER_MODEL`).
3. Review from the report: it has OpenCode's answer, the diffstat, the diff when
   short, and the check result. Exit 0 means finished and check passed; other
   codes are in `~/.claude/skills/delegate-to-opencode/references/worker.md`.
   If the diff was not printed, do one targeted read (`git diff <baseline> --
   <file>` or `grep`), not a full read. Look for weakened tests, hardcoded
   success, swallowed errors and nonexistent APIs. Fix small problems yourself.
4. Do not trust OpenCode's claims, only the check and the diff. Do not commit
   unless asked.
