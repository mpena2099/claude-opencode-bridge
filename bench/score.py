#!/usr/bin/env python3
"""Scores benchmark runs: Opus cost and turns from the session JSON, quality
from the task's own check.py. Usage: bench/score.py <task> <out-dir>"""

import json
import os
import subprocess
import sys

bench = os.path.dirname(os.path.abspath(__file__))
task, out = sys.argv[1], sys.argv[2]
check = os.path.join(bench, "tasks", task, "check.py")

for name in sorted(os.listdir(out)):
    if not name.endswith(".jsonl"):
        continue
    run = name[:-6]
    events = []
    with open(os.path.join(out, name)) as f:
        for line in f:
            try:
                events.append(json.loads(line))
            except ValueError:
                pass
    result = next((e for e in events if e.get("type") == "result"), None)
    if not result or not result.get("modelUsage"):
        err = open(os.path.join(out, run + ".err")).read().strip()[:120]
        print(f"{run}: no result {err}")
        continue
    calls = [c for e in events if e.get("type") == "assistant"
             for c in e["message"]["content"] if c.get("type") == "tool_use"]
    tools = ",".join(c["name"] + (f"({c['input'].get('skill')})" if c["name"] == "Skill" else "")
                     for c in calls)
    delegated = any("claude-opencode-worker" in json.dumps(c.get("input", {})) for c in calls)
    usage = next(iter(result["modelUsage"].values()))
    quality = subprocess.run([sys.executable, check, os.path.join(out, run)],
                             capture_output=True, text=True).stdout.strip()
    print(f"{run}: ${result['total_cost_usd']:.3f} turns={result['num_turns']} "
          f"out={usage['outputTokens']} cache_write={usage['cacheCreationInputTokens']} "
          f"cache_read={usage['cacheReadInputTokens']} "
          f"{'delegated' if delegated else 'self'} | {quality} | {tools}")
