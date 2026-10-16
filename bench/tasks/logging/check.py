#!/usr/bin/env python3
"""Quality of the print-to-logging change: tests pass, no print() left, every
module has a logger, and WARN/ERROR messages went to the right level without
their prefix."""

import glob
import os
import re
import subprocess
import sys

run = sys.argv[1]
p = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-t", "."],
                   cwd=run, capture_output=True, text=True, timeout=120)
modules = [f for f in glob.glob(os.path.join(run, "app", "*.py")) if not f.endswith("__init__.py")]
prints = loggers = wrong = 0
for path in modules:
    s = open(path).read()
    prints += s.count("print(")
    loggers += "getLogger(__name__)" in s
    wrong += len(re.findall(r'logger\.\w+\(f?"(WARN|ERROR): ', s))
    wrong += len(re.findall(r'logger\.(info|error)\(f?"[^"]*negative', s))
    wrong += len(re.findall(r'logger\.(info|warning)\(f?"[^"]*failed for', s))
print(f"{'pass' if p.returncode == 0 else 'FAIL'} prints_left={prints} "
      f"loggers={loggers}/{len(modules)} wrong_level_or_prefix={wrong}")
