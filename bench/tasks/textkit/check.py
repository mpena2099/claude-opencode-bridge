#!/usr/bin/env python3
"""Quality of a generated test_textkit.py: does it pass, how many tests, and
how many of 10 planted bugs (one per function) it catches."""

import os
import re
import shutil
import subprocess
import sys
import tempfile

run = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, "fixture", "textkit.py")).read()
MUTANTS = [
    ("slugify", 'return text[:max_len].rstrip("-")', "return text[:max_len]"),
    ("truncate", "if len(text) <= width:", "if len(text) < width:"),
    ("word_count", "return len(text.split())", 'return len(text.split(" "))'),
    ("title_case", "w if i > 0 and w in small_words", "w if w in small_words"),
    ("parse_duration", "return h * 3600 + m * 60 + s", "return h * 3600 + m * 60"),
    ("format_bytes", "if size < 1024 or", "if size <= 1024 or"),
    ("mask_email", "if not user or not domain:", "if not user:"),
    ("wrap", "len(current) + 1 + len(word) <= width", "len(current) + len(word) <= width"),
    ("dedupe_preserve", "return [x for x in items if not (x in seen or seen.add(x))]",
     "return list(dict.fromkeys(reversed(items)))[::-1]"),
    ("count_vowels", 'unicodedata.normalize("NFKD", text).lower()', "text.lower()"),
]


def unittest(cwd):
    p = subprocess.run([sys.executable, "-m", "unittest", "-q"], cwd=cwd,
                       capture_output=True, text=True, timeout=120)
    m = re.search(r"Ran (\d+) test", p.stderr)
    return p.returncode == 0, int(m.group(1)) if m else 0


tests = os.path.join(run, "test_textkit.py")
if not os.path.exists(tests):
    print("no test_textkit.py")
    sys.exit()
untouched = open(os.path.join(run, "textkit.py")).read() == src
ok, count = unittest(run)
missed = []
for name, old, new in MUTANTS:
    with tempfile.TemporaryDirectory() as tmp:
        shutil.copy(tests, tmp)
        with open(os.path.join(tmp, "textkit.py"), "w") as f:
            f.write(src.replace(old, new, 1))
        if unittest(tmp)[0]:
            missed.append(name)
print(f"{'pass' if ok else 'FAIL'} tests={count} bugs_caught={10 - len(missed)}/10"
      f"{' missed=' + ','.join(missed) if missed else ''}"
      f"{'' if untouched else ' TEXTKIT_CHANGED'}")
