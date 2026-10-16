#!/usr/bin/env python3
"""Writes the fixture into the current directory: 12 modules under app/ that
log with print(), 75 calls in all, and unittest tests for their return
values."""

import os
import random

random.seed(7)
NAMES = ["orders", "users", "billing", "inventory", "shipping", "reports",
         "auth", "search", "cart", "reviews", "coupons", "alerts"]
OPS = ["+", "-", "*"]

os.makedirs("app", exist_ok=True)
os.makedirs("tests", exist_ok=True)
open("app/__init__.py", "w").close()
open("tests/__init__.py", "w").close()
with open("README.md", "w") as f:
    f.write("# shop\n\nTests: `python3 -m unittest discover -s tests -t .`\n")

for n in NAMES:
    code = [f'"""{n.capitalize()} service helpers."""\n\n']
    tests = [f"import unittest\n\nfrom app import {n}\n\n\nclass Test{n.capitalize()}(unittest.TestCase):\n"]
    for i in range(4):
        fn = f"{n}_step{i}"
        sym = random.choice(OPS)
        k = random.randint(2, 9)
        kind = random.choice(["info", "info", "warn", "error"])
        msg = {
            "info": f'f"{n} step {i} with {{value}}"',
            "warn": f'f"WARN: {n} step {i} got negative {{value}}"',
            "error": f'f"ERROR: {n} step {i} failed for {{value}}"',
        }[kind]
        code.append(f"def {fn}(value):\n")
        if kind == "info":
            code.append(f"    print({msg})\n    return value {sym} {k}\n\n\n")
        else:
            code.append(f"    if value < 0:\n        print({msg})\n        return 0\n"
                        f'    print(f"{n} step {i} ok")\n    return value {sym} {k}\n\n\n')
        v = random.randint(1, 20)
        tests.append(f"    def test_{fn}(self):\n        self.assertEqual({n}.{fn}({v}), {eval(f'{v}{sym}{k}')})\n")
        if kind != "info":
            tests.append(f"        self.assertEqual({n}.{fn}(-1), 0)\n")
    with open(f"app/{n}.py", "w") as f:
        f.write("".join(code).rstrip() + "\n")
    with open(f"tests/test_{n}.py", "w") as f:
        f.write("".join(tests))
