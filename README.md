# Claude Code → OpenCode Delegation Bridge

A small, version-controlled setup for delegating straightforward coding tasks from Claude Code to OpenCode, with the main Opus session performing the final review.

## What this project does

When Claude Code is running with Opus, the `delegate-to-opencode` skill can be selected automatically for simple, mechanical, repetitive, or well-defined coding tasks. The skill invokes `claude-opencode-worker`, which runs OpenCode in non-interactive mode. After the worker finishes, the main Opus session reviews the diff and validation results before accepting the work as complete.

When Claude Code is running with Sonnet, the skill explicitly tells the model not to use this workflow. This behavior was validated manually in Claude Code.

The setup does **not** disable or replace Claude Code's normal subagents. Explore, Plan, general-purpose, and user-defined subagents remain available.

## Architecture

```text
Claude Code / Opus
        |
        | automatic skill selection
        v
 delegate-to-opencode
        |
        v
 claude-opencode-worker
        |
        v
    opencode run
        |
        v
 OpenCode build agent
        |
        v
 configured OpenCode model
        |
        v
  implementation result
        |
        v
Main Opus session reviews diff + tests
        |
        v
      accepted
```

For the validated setup, OpenCode reported version `1.18.34` and used `muse-spark-1.3-contributor-free` for the delegated test.

## Files

- `skills/delegate-to-opencode/SKILL.md`: Claude Code skill definition, including the Opus-only delegation rule and mandatory main-session review.
- `bin/claude-opencode-worker`: wrapper that launches OpenCode with a timeout and git guardrails.
- `install.sh`: installs the skill and wrapper into the expected user directories.
- `uninstall.sh`: removes the installed files while creating a timestamped backup first.
- `tests/test-install.sh`: verifies the installed files match the repository and checks basic metadata.
- `tests/test-worker.sh`: exercises the worker against a stub `opencode`, without calling any model.
- `.github/workflows/ci.yml`: runs ShellCheck, the worker tests and an install/uninstall cycle in a temporary `HOME`.
- `VERSION`: project/configuration version.

## Installation

Clone or extract this repository, then run:

```bash
./install.sh
```

The installer places:

```text
~/.claude/skills/delegate-to-opencode/SKILL.md
~/.local/bin/claude-opencode-worker
```

It creates a timestamped backup if either target file already exists.

## Requirements

- Claude Code with support for Skills.
- OpenCode installed and available as `opencode` in `PATH`.
- A working OpenCode `build` agent.

The worker does not force an OpenCode model. By default, OpenCode uses its configured default model. To override it for one invocation, set:

```bash
export OPENCODE_WORKER_MODEL='provider/model'
```

Then run Claude Code normally.

The worker stops OpenCode after 570 seconds and exits with code 124, staying below the 600-second maximum of Claude Code's Bash tool. Override it with:

```bash
export OPENCODE_WORKER_TIMEOUT=300
```

## Tests

```bash
./tests/test-worker.sh    # worker behavior, no OpenCode or model needed
./tests/test-install.sh   # installed files match this repository
```

CI runs both, plus ShellCheck and an install/uninstall cycle in a temporary `HOME`.

## Manual verification

### Verify the worker directly

From a project directory:

```bash
claude-opencode-worker <<'TASK'
Create a file named opencode-delegation-test.txt containing exactly two lines: DELEGATION_TEST and Executed by an external worker.
TASK
```

The task can also be passed as arguments, but stdin through a quoted heredoc keeps `$`, backticks and quotes literal. The skill tells Claude to use the heredoc form.

### Verify automatic delegation with Opus

Use a simple task and do **not** explicitly invoke the skill. For example:

```text
Create a file named opencode-delegation-test.txt in the current directory containing exactly these two lines:

DELEGATION_TEST
Executed by an external worker

The task is deliberately simple. After completing it, verify the file and tell me how the task was executed.
```

Evidence of actual delegation should include something like:

```text
Skill(delegate-to-opencode)
Bash(~/.local/bin/claude-opencode-worker ...)
=== OpenCode Worker ===
OpenCode: ...
```

### Verify the Opus review step

For a delegated task, the main Opus session should continue after OpenCode
finishes and inspect the resulting diff and relevant tests. Evidence should
show that the OpenCode command completed first, followed by Claude Code
reading/reviewing the changed files and running validation as appropriate.

### Verify non-delegation with Sonnet

Repeat the same task in a Sonnet session. The expected behavior is that Claude Code uses its own file-writing tool instead of invoking the OpenCode wrapper.

## Safety boundaries

The skill tells Claude not to delegate:

- architecture decisions
- ambiguous requirements
- security-sensitive decisions
- difficult debugging that needs substantial reasoning
- work where the correct implementation approach is unclear

The worker blocks destructive Git operations in two layers, both scoped to delegated runs only:

1. **Permission rules enforced by OpenCode.** The worker sets `OPENCODE_CONFIG_CONTENT` with `deny` rules for `git commit`, `push`, `reset`, `clean`, `checkout`, `switch`, `restore`, `stash`, `rebase` and `merge`. Patterns start with `*` because command-rewriting plugins such as rtk turn `git commit` into `rtk git commit` before permissions are evaluated. Your regular OpenCode sessions are not affected. If `OPENCODE_CONFIG_CONTENT` is already set, the worker keeps yours and warns that its rules are not applied.
2. **Prompt instructions.** The task is prefixed with an instruction to leave changes uncommitted and stay inside the project directory, so the model does not waste turns on denied commands.

This is a guardrail, not a sandbox. A pattern-based rule does not catch forms like `git -C . commit` or a script that calls git, and the `build` agent can still edit any file in the project. The main session's diff review remains the real safety check.

### OpenCode non-interactive behavior

Verified with OpenCode 1.18.34:

- Any permission that resolves to `ask` is auto-rejected in `opencode run` (`permission requested: ...; auto-rejecting`). The run does not hang waiting for approval.
- The process still exits with code 0 after a rejected tool call, so the exit code does not indicate success. The skill tells Claude to check the output and the diff.
- `--auto` would approve every permission that is not explicitly denied. The worker does not use it.

## Important behavior

The Opus/Sonnet distinction is a model instruction inside the skill, not a hard programmatic router. The validated behavior is:

```text
Opus   → may automatically load the skill for suitable tasks
Sonnet → told not to use the skill
```

This repository does not implement ACP. OpenCode is used through `opencode run`, because the current setup does not require an ACP bridge.

## Restoring the setup later

```bash
./install.sh
```

The installer will back up an existing target before replacing it.

## Uninstall

```bash
./uninstall.sh
```

The uninstall script backs up the current installed files before removing them.

## Security

This repository must not contain:
- API keys
- tokens
- credentials
- personal Claude Code config files
- `.env` files
- conversation history

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
