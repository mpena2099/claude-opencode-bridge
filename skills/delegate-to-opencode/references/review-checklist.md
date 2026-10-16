# Review checklist for delegated work

Use this on every diff OpenCode produces, before telling the user the task is
done. Green tests are necessary, not sufficient: generated code fails in ways
a passing gate does not show.

## 1. Tests first

If the diff touches existing tests, review those edits before trusting any
test run. A weakened test makes the run measure less than it did before.

- Edits to existing tests that the task did not ask for: flag them to the
  user, do not keep them silently.
- New `skip`, `only`, `xit`, commented-out tests, or deleted tests: treat the
  underlying test as failing until shown otherwise.
- Loosened assertions (exact match turned into `contains` or truthy, broader
  error types, wider tolerances): same treatment.

## 2. Re-run the checks yourself

OpenCode's "tests pass" is a claim. Run the project's real test, lint, type
and build commands and read the output.

- Migrations or schema changes: apply them on a local or scratch database
  and check the result; never against production.
- Removals or renames: search the codebase for references left behind.
- Stateful behaviour: exercise it, do not only check that it compiles.

## 3. Diff against the task

- Scope creep: changes to files or behaviour the task said to leave alone,
  unrequested refactors, renames, "while I was here" edits.
- Shortfall: edge cases, cleanup, or parts of the task left undone.
- Quiet decisions: choices the task did not anticipate. Understand them and
  decide; tell the user about the ones that matter.

## 4. Failure patterns tests do not catch

- Hardcoded success, canned responses or fixture data on a path that should
  do real work.
- Catch-all error handling that returns a default instead of propagating the
  error.
- Imports, methods or signatures that do not exist in the installed version
  of a dependency. Check the lockfile or the package, not plausibility.
- Dead code: unused imports, helpers nothing calls, unreachable branches,
  leftover debug output, "Step 1/Step 2" comments.
- Secrets, URLs or environment-specific values written into code.

## 5. Decide

- Everything holds: report to the user what changed and what you verified.
- Something needs fixing: send only the correction to the same OpenCode
  session (see "Fixing after review" in references/worker.md) and review again, or fix it
  yourself if it is small.
- The fix needs a design decision or goes beyond the task: stop and ask the
  user.
