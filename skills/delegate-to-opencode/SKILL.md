---
name: delegate-to-opencode
description: >
  Use proactively for straightforward, mechanical, repetitive, or well-defined
  coding tasks when the current main model is Opus. Delegate routine
  implementation, tests, simple refactors, repetitive edits, and file creation
  to OpenCode. After OpenCode finishes, the main Opus session must review the
  resulting changes and tests before considering the delegated work complete.
  Do not use when the current model is Sonnet. Do not delegate architectural
  decisions, ambiguous requirements, security-sensitive work, or difficult
  debugging.
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

## Delegation workflow

When delegation is appropriate:

1. Preserve all relevant requirements from the user's request.
2. Give OpenCode enough context to perform the implementation independently.
3. Run:

   `~/.local/bin/claude-opencode-worker "<task>"`

4. Wait for OpenCode to finish.
5. Treat OpenCode's output as an implementation attempt, not as final approval.
6. Inspect the resulting git diff yourself as the main Claude Code session.
7. Run the relevant tests, checks, linters, or other validation yourself when appropriate.
8. Review the implementation against the original requirements, including scope,
   correctness, regressions, and unintended changes.
9. Only after this review should you consider the delegated task complete.

The review in steps 6-8 should be performed by the main Claude Code session
(the Opus session that delegated the work), not silently delegated back to
OpenCode.

Do not blindly trust OpenCode's conclusions or its statement that tests pass.

Do not commit changes unless the user explicitly requested a commit.

Do not reset, clean, checkout, or discard existing user changes.

If the task is not appropriate for delegation, implement it directly.
