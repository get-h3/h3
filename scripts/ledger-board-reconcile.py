#!/usr/bin/env python3
"""ledger-board-reconcile — reconcile the stand-in PM ledger against the project boards.

Answers DF-H3PM-03 (h3 tick #397).

THE FINDING
    The stand-in PM lane keeps a fleet-wide ledger at ~/.hermes/stand-in/ledger.json.
    Its items carry a status of their own (added / picked_up / verified / stale /
    blocked) and it was never checked against the per-project boards, so it drifts:
    at tick fire 154 items were status added/picked_up while 60 of them were already
    status=complete on their project's board and 5 had no matching board row at all.
    The consequence burns budget on both sides — the PM digest and cycle report
    overstate outstanding work, and the next prior-run pass re-checks rows the foremen
    already closed.

WHAT THIS TOOL DOES
    Reads each swept project's board (JSONL-canonical at
    <workdir>/.coding-hermes/board/tasks.jsonl, resolved through the scheduler db) and
    classifies every ledger item whose status is added or picked_up:

        ALREADY_COMPLETE  the board has a row with that id, status in
                          {complete, closed, done, cancelled}
        STILL_OPEN        the board has a row with that id, any other status
        NO_BOARD_ROW      no board file, or no row with that id

READ-ONLY BY DEFAULT
    Without --apply the tool only reads and prints a report; the ledger is never
    opened for writing. --apply is additive-only and touches ONLY the
    ALREADY_COMPLETE items.

WHY STILL_OPEN ITEMS ARE NEVER AUTO-CLOSED
    A board row that exists with a non-terminal status is the board's own answer: the
    work is not closed there. The ledger disagreeing with it is a disagreement to NAME
    in the cycle report, not one to resolve by writing a status the board does not
    support. Same for NO_BOARD_ROW: the 5 hivemind-work rows (HW-GAP-006..010) have no
    board row, and the honest report says so instead of closing them by inference.
    Only work the board itself marks terminal may be stamped verified in the ledger.

PM-LANE LOCKOUT
    The ledger is single-writer: while a project's PM lane is running, that lane owns
    the file and a concurrent read-modify-write would drop its updates. --apply
    therefore probes the local scheduler tick API first and refuses to write (exit 3)
    when any running tick's project_name ends with "-pm". An unreachable API is also
    exit 3 — the tool cannot prove the lane is idle — unless --apply is combined with
    an explicit --force.

Exit codes: 0 success, 1 ledger missing/unparseable, 2 usage error, 3 apply refused.
"""

import argparse
import fcntl
import json
import os
import shutil
import sqlite3
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

DEFAULT_LEDGER = os.path.expanduser("~/.hermes/stand-in/ledger.json")
DEFAULT_DB = os.path.expanduser("~/.hermes/coding-hermes/scheduler.db")
TICKS_URL = "http://localhost:9090/api/v1/ticks"
BOARD_REL = os.path.join(".coding-hermes", "board", "tasks.jsonl")
TOOL_NAME = "scripts/ledger-board-reconcile.py"

# Statuses that mean "the board considers this work finished".
DONE_STATUSES = ("complete", "closed", "done", "cancelled")
# Ledger statuses this tool reconciles. Everything else is left alone.
OPEN_STATUSES = ("added", "picked_up")
# Provenance recorded on each reconciled item.
RECONCILER_CONTEXT = "h3 tick #397"
TITLE_WIDTH = 64

EXIT_OK = 0
EXIT_LEDGER = 1
EXIT_USAGE = 2
EXIT_REFUSED = 3


def utc_timestamp():
    """UTC ISO-8601, second precision, e.g. 2026-09-19T03:55:12Z."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_ledger(path):
    """Return the ledger dict, or exit 1 when it is missing or unparseable."""
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except FileNotFoundError:
        print("ledger missing: %s" % path, file=sys.stderr)
        sys.exit(EXIT_LEDGER)
    except (OSError, ValueError) as exc:
        print("ledger unparseable: %s: %s" % (path, exc), file=sys.stderr)
        sys.exit(EXIT_LEDGER)
    if not isinstance(data, dict) or not isinstance(data.get("items"), list):
        print("ledger has no 'items' list: %s" % path, file=sys.stderr)
        sys.exit(EXIT_LEDGER)
    return data


def project_workdirs(db_path):
    """Map project name -> workdir. A missing/unreadable db yields {} (loudly)."""
    if not os.path.isfile(db_path):
        print("WARNING: scheduler db not found: %s (every project is unresolved)" % db_path,
              file=sys.stderr)
        return {}
    try:
        con = sqlite3.connect("file:%s?mode=ro" % db_path, uri=True)
        try:
            rows = con.execute("SELECT name, workdir FROM projects").fetchall()
        finally:
            con.close()
    except sqlite3.Error as exc:
        print("WARNING: scheduler db unreadable (%s): %s" % (db_path, exc), file=sys.stderr)
        return {}
    return {str(name): workdir for name, workdir in rows}


def read_board(workdir):
    """Return {id: row} for the project's board, or None when it has no board file.

    Rows may be compact or pretty-printed and legacy lines may be malformed: parse
    line-by-line so one bad line cannot abort the sweep.
    """
    path = os.path.join(workdir, BOARD_REL)
    if not os.path.isfile(path):
        return None
    rows = {}
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if isinstance(row, dict) and row.get("id") is not None:
                rows[str(row["id"])] = row
    return rows


def classify(items, rows):
    """Classify one project's reconcilable ledger items against its board rows.

    Returns (counts, already_complete, no_board_row) where the two lists hold
    (item, board_status) pairs — board_status is None for NO_BOARD_ROW items.
    """
    counts = {"open_items": 0, "already_complete": 0, "still_open": 0, "no_board_row": 0}
    already_complete = []
    no_board_row = []
    for item in items:
        if item.get("status") not in OPEN_STATUSES:
            continue
        counts["open_items"] += 1
        row = None if rows is None else rows.get(str(item.get("id")))
        if row is None:
            counts["no_board_row"] += 1
            no_board_row.append((item, None))
        elif row.get("status") in DONE_STATUSES:
            counts["already_complete"] += 1
            already_complete.append((item, row.get("status")))
        else:
            counts["still_open"] += 1
    return counts, already_complete, no_board_row


def sweep(ledger_items, workdirs, projects):
    """Classify every swept project.

    Returns (per_project, totals, targets, missing_items):
      targets       list of (project, item_id, board_status, title) that --apply may close
      missing_items list of (project, item_id, title) with no matching board row
    """
    per_project = {}
    targets = []
    missing_items = []
    for project in projects:
        items = [i for i in ledger_items if str(i.get("project")) == project]
        workdir = workdirs.get(project)
        rows = read_board(workdir) if workdir else None
        counts, complete, missing = classify(items, rows)
        counts["unresolved_board"] = rows is None
        per_project[project] = counts
        targets.extend((project, str(item["id"]), status, item.get("title"))
                       for item, status in complete)
        missing_items.extend((project, str(item["id"]), item.get("title"))
                             for item, _ in missing)
    totals = {"projects": len(projects),
              "unresolved_board": sum(1 for c in per_project.values() if c["unresolved_board"])}
    for key in ("open_items", "already_complete", "still_open", "no_board_row"):
        totals[key] = sum(c[key] for c in per_project.values())
    return per_project, totals, targets, missing_items


def probe_pm_lanes(url=TICKS_URL, timeout=10):
    """Probe the tick API. Returns (reachable, running PM-lane project names)."""
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8", "replace"))
    except (urllib.error.URLError, OSError, ValueError) as exc:
        print("WARNING: tick API unreachable (%s): %s" % (url, exc), file=sys.stderr)
        return False, []
    ticks = payload.get("ticks") or []
    running = [str(t.get("project_name")) for t in ticks
               if t.get("status") == "running"
               and str(t.get("project_name")).endswith("-pm")]
    return True, running


def reconciled_item(item, timestamp, evidence):
    """Copy of item with status/completed_at/last_checked_at/verification_evidence set.

    Every other key and value is carried over verbatim and in its original order;
    completed_at is inserted next to status.
    """
    new = {}
    for key, value in item.items():
        new[key] = value
        if key == "status":
            new["status"] = "verified"
            new["completed_at"] = timestamp
    if "completed_at" not in new:
        new["completed_at"] = timestamp
    new["last_checked_at"] = timestamp
    new["verification_evidence"] = evidence
    return new


def apply_targets(ledger_path, targets, timestamp):
    """Mutate the ALREADY_COMPLETE items under an exclusive lock on the ledger.

    Returns (items treated, backup path). Nothing is written when there is nothing to
    reconcile. The ledger is re-read inside the lock so a concurrent writer is never
    overwritten, and the result is written to a tmp file in the same directory and
    os.replace()d into place.
    """
    if not targets:
        return 0, None
    board_status = {(project, item_id): status for project, item_id, status, _ in targets}
    with open(ledger_path, "r+", encoding="utf-8") as handle:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        try:
            handle.seek(0)
            data = json.load(handle)
            stamp = utc_timestamp()
            backup = "%s.bak-%s" % (ledger_path,
                                    stamp.replace("-", "").replace(":", ""))
            shutil.copy2(ledger_path, backup)
            items = data.get("items", [])
            treated = 0
            for index, item in enumerate(items):
                key = (str(item.get("project")), str(item.get("id")))
                if key not in board_status or item.get("status") not in OPEN_STATUSES:
                    continue
                evidence = ("board row %s/%s status=%s — reconciled by %s (%s)"
                            % (key[0], key[1], board_status[key], TOOL_NAME, RECONCILER_CONTEXT))
                items[index] = reconciled_item(item, stamp, evidence)
                treated += 1
            tmp_path = "%s.tmp.%d" % (ledger_path, os.getpid())
            with open(tmp_path, "w", encoding="utf-8") as out:
                json.dump(data, out, indent=1, ensure_ascii=False)
            os.replace(tmp_path, ledger_path)
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
    return treated, backup


def truncate(text, width=TITLE_WIDTH):
    text = " ".join(str(text or "").split())
    return text if len(text) <= width else text[:width - 1] + "…"


def print_report(ledger_path, db_path, applied, per_project, totals, targets, missing_items):
    print("ledger-board-reconcile — DF-H3PM-03 (%s, %s)" % (TOOL_NAME, RECONCILER_CONTEXT))
    print("ledger: %s" % ledger_path)
    print("db:     %s" % db_path)
    print("mode:   %s" % ("APPLY (additive, ALREADY_COMPLETE only)" if applied else
                          "dry run (read-only; pass --apply to write)"))
    print("")
    print("%-34s %6s %6s %6s %6s %s" % ("project", "open", "compl", "still", "no_row", "board"))
    for project in sorted(per_project,
                          key=lambda p: (-per_project[p]["already_complete"], p)):
        counts = per_project[project]
        print("%-34s %6d %6d %6d %6d %s" % (project, counts["open_items"],
                                            counts["already_complete"], counts["still_open"],
                                            counts["no_board_row"],
                                            "UNRESOLVED" if counts["unresolved_board"] else "ok"))
    print("%-34s %6d %6d %6d %6d %d unresolved project(s)" %
          ("TOTALS (%d swept)" % totals["projects"], totals["open_items"],
           totals["already_complete"], totals["still_open"], totals["no_board_row"],
           totals["unresolved_board"]))
    if targets:
        print("")
        print("ALREADY_COMPLETE — %d item(s) the board already closed:" % len(targets))
        for project, item_id, status, title in sorted(targets):
            print("  %s %s [board=%s] %s" % (project, item_id, status, truncate(title)))
    if missing_items:
        print("")
        print("NO_BOARD_ROW — %d item(s) with no matching board row (named, not closed):"
              % len(missing_items))
        for project, item_id, title in sorted(missing_items):
            print("  %s %s %s" % (project, item_id, truncate(title)))


def json_payload(ledger_path, db_path, applied, before, after):
    payload = {"ledger": ledger_path, "db": db_path, "applied": applied,
               "before": {"projects": before[0], "totals": before[1]}}
    if after is not None:
        payload["after"] = {"projects": after[0], "totals": after[1]}
    return payload


def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog="ledger-board-reconcile.py",
        description="Reconcile the stand-in PM ledger against the project boards "
                    "(read-only unless --apply).",
        epilog="Exit codes: 0 ok, 1 ledger missing/unparseable, 2 usage, 3 --apply refused "
               "(PM lane running, or tick API unreachable without --force).")
    parser.add_argument("--project", action="append", metavar="NAME",
                        help="sweep this project (repeatable)")
    parser.add_argument("--all", action="store_true", help="sweep every project in the ledger")
    parser.add_argument("--apply", action="store_true",
                        help="write the reconciliation (ALREADY_COMPLETE items only)")
    parser.add_argument("--force", action="store_true",
                        help="allow --apply when the tick API is unreachable")
    parser.add_argument("--json", action="store_true", help="emit one JSON object on stdout")
    parser.add_argument("--ledger", default=DEFAULT_LEDGER, help="ledger path")
    parser.add_argument("--db", default=DEFAULT_DB, help="scheduler db path")
    args = parser.parse_args(argv)
    if not args.all and not args.project:
        parser.print_usage(sys.stderr)
        print("ledger-board-reconcile: choose --all or at least one --project NAME",
              file=sys.stderr)
        sys.exit(EXIT_USAGE)
    return args


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)
    ledger_path = os.path.abspath(os.path.expanduser(args.ledger))
    db_path = os.path.abspath(os.path.expanduser(args.db))

    ledger = load_ledger(ledger_path)
    items = ledger["items"]

    if args.apply:
        reachable, pm_lanes = probe_pm_lanes()
        if pm_lanes:
            print("ABORT: %s PM lane is running — the ledger is owned by that lane while it runs"
                  % pm_lanes[0])
            sys.exit(EXIT_REFUSED)
        if not reachable and not args.force:
            print("ABORT: tick API unreachable and --force was not given — cannot prove the "
                  "PM lane is idle")
            sys.exit(EXIT_REFUSED)

    projects = args.project if args.project else sorted(
        {str(i.get("project")) for i in items})
    workdirs = project_workdirs(db_path)
    per_project, totals, targets, missing_items = sweep(items, workdirs, projects)

    treated = 0
    backup = None
    after = None
    if args.apply:
        treated, backup = apply_targets(ledger_path, targets, utc_timestamp())
        refreshed = load_ledger(ledger_path)["items"]
        after_projects, after_totals = sweep(refreshed, workdirs, projects)[:2]
        after = (after_projects, after_totals)

    if args.json:
        print(json.dumps(json_payload(ledger_path, db_path, args.apply,
                                      (per_project, totals), after), indent=2))
        return EXIT_OK

    print_report(ledger_path, db_path, args.apply, per_project, totals, targets, missing_items)
    if args.apply:
        print("")
        print("items treated: %d" % treated)
        print("backup:        %s" % (backup or "none (nothing to reconcile — no mutation)"))
        print("before:        %s" % json.dumps(totals, sort_keys=True))
        print("after:         %s" % json.dumps(after[1], sort_keys=True))
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
