# Benchmark

Measures what delegating saves in real Opus sessions. Each run is a fresh
`claude -p --model opus` session in a throwaway git repository, so it costs
real usage on the account that runs it (about $0.30 to $0.45 per session).

```bash
bench/run.sh textkit /tmp/bench-textkit N1 N2 C1 C2
bench/score.py textkit /tmp/bench-textkit      # re-score without re-running
```

Conditions: `N` Opus alone, `A` skill available but not mentioned, `F` prompt
asks for the skill, `C` prompt sent through `/delegate`. Install the bridge
first (`./install.sh`): sessions use the installed skill and command.

Tasks, under `tasks/`:

- `textkit`: write a unittest suite for a 10-function module. Quality is
  checked against 10 planted bugs, one per function.
- `logging`: replace 75 `print()` calls with `logging` across 12 modules.
  Quality is checked for leftover prints, loggers and log levels.

A task is a directory with `prompt.txt`, either a `fixture/` directory or an
executable `make_fixture.py`, and an executable `check.py <run-dir>` that
prints one line about quality. Compare conditions within the same batch:
sessions started together share the prompt cache, which shifts cost between
them.
