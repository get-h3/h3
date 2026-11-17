#!/usr/bin/env python3
"""Append the verbatim JSON-only failure line to DF-H3-54."""

import json

BOARD = "/home/kara/get-h3/h3/.coding-hermes/board/tasks.jsonl"
ADD = (
    "\nVerbatim JSON payload for that failure (h3-test --json, arm D): "
    "process_text_finished_false [Process Basic Flows] - Expected finished=false, got True "
    "(battery convention: a message containing 'do not finish' must return text with finished=false - "
    "see docs/integration.md Partial turns). That actionable string exists in --json and has no "
    "counterpart anywhere in the 15-line human report, which is why a user cannot tell a harness bug "
    "from a documented convention."
)
TARGET = "DF-H3-54"

lines = open(BOARD, encoding="utf-8").readlines()
hits = [
    i
    for i, line in enumerate(lines)
    if line.strip() and json.loads(line).get("id") == TARGET
]
assert len(hits) == 1, f"expected exactly 1 row for {TARGET}, got {hits}"
row = json.loads(lines[hits[0]])
row["detail"] = row["detail"] + ADD
lines[hits[0]] = json.dumps(row, ensure_ascii=False) + "\n"
with open(BOARD, "w", encoding="utf-8") as fh:
    fh.writelines(lines)
print(TARGET, "detail_chars =", len(row["detail"]))
