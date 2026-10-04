#!/usr/bin/env python3
"""gate-verdict.py — run a DuckBrain census guard and classify its verdict.

Usage: python3 scripts/gate-verdict.py <guard-cmd> [args...]

Wraps the repo's DuckBrain census guards (check-duckbrain-tick-chain.sh,
duckbrain-tree-census.py) for the make verify composition (DF-H3-46):

  guard prints VERDICT: VERIFIED   -> exit 0 (gate green, evidence real)
  guard prints VERDICT: FAILED     -> exit 1 (real failure propagates)
  guard prints VERDICT: UNVERIFIED -> exit 3 (refuse: an unchecked substrate
                                      must not compose green into make verify)

The caller (Makefile verify-tick-chain target) turns exit 3 into a loud
H3_GATE_ALLOW_UNVERIFIED=1 opt-in or a hard FAIL. UNVERIFIED is honest as a
report and corrosive as an exit code — it never passes through as 0.
"""
import subprocess
import sys


def main() -> int:
    if len(sys.argv) < 2:
        print("gate-verdict: usage: gate-verdict.py <guard-cmd> [args...]", file=sys.stderr)
        return 2
    try:
        p = subprocess.run(sys.argv[1:], capture_output=True, text=True, timeout=300)
    except FileNotFoundError as e:
        print("gate-verdict: guard not runnable: %s" % e, file=sys.stderr)
        return 2
    sys.stdout.write(p.stdout)
    sys.stderr.write(p.stderr)
    for line in (p.stdout + p.stderr).splitlines():
        if line.startswith("VERDICT: VERIFIED"):
            return 0
        if line.startswith("VERDICT: FAILED"):
            return 1
        if line.startswith("VERDICT: UNVERIFIED") or line.startswith("VERDICT: UNVERIFIED".replace("UNVERIFIED", "UNVERIFIED")):
            return 3
    # No verdict line at all: the guard changed shape — treat as refusal.
    print("gate-verdict: guard produced no VERDICT line — refusing (gate shape changed)", file=sys.stderr)
    return 3


if __name__ == "__main__":
    sys.exit(main())
