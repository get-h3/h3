#!/usr/bin/env python3
"""Set the evidence body on three freshly-created DF-H3 rows.

boardctl create has no --detail flag (and --meta detail=... is silently
dropped, leaving detail={"fingerprint": ...}), so the real-use evidence is
written here: one surgical rewrite of the LAST line carrying each id, every
other line byte-identical, in the same order.
"""

import json
import shutil
import sys
from datetime import datetime, timezone

BOARD = "/home/kara/get-h3/h3/.coding-hermes/board/tasks.jsonl"
BACKUP = (
    "/home/kara/.hermes/cache/scratch/h3-dogfood-20261116/tasks.jsonl.bak-DF-H3-52-54"
)

D52 = """Live 2026-11-16 dogfood, clean venv install of the PyPI wheel (python 3.14):
- installed distribution: site-packages/h3_harness_sdk-0.1.6.dist-info (distribution name h3-harness-sdk)
- served identity: GET /v1/health reports version=0.1.5. h3-test banner, verbatim: Target health: version=0.1.5 uptime_seconds=827 active_sessions=0
- cause: src/h3_harness/_version.py:9 hardcodes __version__ = "0.1.5" while pyproject.toml:7 declares version = "0.1.6". harness.py:350 serves version=__version__ in the health payload and __init__.py:3 re-exports the same constant.
Impact: the identity line exists so a client or CI job can prove WHICH build it is testing (DF-H3-26). Against a healthy 0.1.6 install it reports 0.1.5, so an equality check against the installed package disagrees with reality and a genuine two-version drift stays invisible. The same wrong string is what harness authors paste into bug reports, so triage starts from a false premise.
Fix options: derive the runtime version from installed metadata (importlib.metadata.version for the distribution, with the literal as a source-checkout fallback), or keep the literal and add a release gate that fails when _version.py and pyproject.toml disagree."""

D53 = """Evidence class: static reading of the shipped sdk-python 0.1.6 wheel plus battery v0.1.0 source. The live DELETE probe was NOT run this tick (consent-blocked), so acceptance criterion 1 is the live confirmation.
Router: src/h3_harness/harness.py:615-629. DELETE calls await harness.on_session_terminate(session_id) at 626; BaseHarness.on_session_terminate at 123-129 returns None and its docstring says the base implementation is a no-op. The router then calls _track(harness, session_id, "completed") at 628 and returns {"session_id": ..., "terminated": True} at 629. For any harness that does not override the hook, DELETE therefore reports success while the harness session state is untouched, and the status a later GET reports was manufactured by the router rather than by the product. Line 628 was added by DF-H3-SDK-PYTHON-FOREMAN-5 to stop terminated sessions looking live, but it writes completed, the same string a normal END writes at 544, so an ended session and a deleted session are indistinguishable to a client.
Gate: shim/src/h3_shim/test_battery.py:2089-2099 states the intent (terminate handling is only real if the harness own session view agrees) but the acceptance at 2152-2154 passes status in (completed, terminated, cancelled, expired). completed is exactly what the router just wrote, so the check cannot tell a real teardown from a fabricated stamp, and it also cannot see that DELETE and END are indistinguishable.
Impact: a client or the shim session reaper that trusts terminated:true drops its own bookkeeping while the session survives, and the compliance battery reports PASS for that harness.
Related: SDKPY-GAP-044 (closed, documentation only) documented the contract for harnesses that override the hook; the residual gap is the wire claim for harnesses that do not, plus the battery check that cannot detect it."""

D54 = """Live 2026-11-16, h3-test against an SDK-derived harness that answers finished=false on one documented case. The complete text output is 15 lines: header (H3 Compliance Test Battery v0.1.0), Target, Transport, one tally line per category (for example Process Basic Flows 7/8 FAILED), TOTAL 47/48 FAILED, Duration, Latency p50/p95. No failing test name, no detail string, and no pointer to --json.
Cause: shim/src/h3_shim/cli.py:432-463 (_format_human) iterates categories and prints passed/total at 452 and the totals at 455; the per-test detail that the JSON report carries is never rendered. The failing case here was a documented convention (finished=false), which the text output gave no way to recognise, so a user reads a correct harness as broken.
Impact: the documented primary workflow is run h3-test and read the summary. When it is red the user must already know --json exists and own a JSON parser to learn which of 48 checks failed; the difference between a harness bug and a documented convention is invisible in the human report.
Fix: after the TOTAL line, when not report.all_passing, print each failing test name with the first line of its detail (cap around 10 lines, then a count of the remainder), plus one hint line telling the user to rerun with --json for per-test detail. Exit code semantics unchanged."""

ROWS = {"DF-H3-52": D52, "DF-H3-53": D53, "DF-H3-54": D54}


def main() -> int:
    with open(BOARD, "r", encoding="utf-8") as fh:
        lines = fh.readlines()
    shutil.copyfile(BOARD, BACKUP)

    last_index = {}
    for i, line in enumerate(lines):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        rid = row.get("id")
        if rid in ROWS:
            last_index[rid] = i

    missing = [rid for rid in ROWS if rid not in last_index]
    if missing:
        print("MISSING rows, nothing written:", missing, file=sys.stderr)
        return 2

    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    for rid, text in ROWS.items():
        i = last_index[rid]
        row = json.loads(lines[i])
        row["detail"] = text
        row["updated_at"] = now
        lines[i] = json.dumps(row, ensure_ascii=False) + "\n"

    if len(lines) != len(open(BOARD, "r", encoding="utf-8").readlines()):
        print("line count changed, aborting", file=sys.stderr)
        return 3

    with open(BOARD, "w", encoding="utf-8") as fh:
        fh.writelines(lines)

    for rid in ROWS:
        print(rid, "detail_chars=", len(ROWS[rid]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
