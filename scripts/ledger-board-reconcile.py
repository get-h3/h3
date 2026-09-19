#!/usr/bin/env python3
"""ledger-board-reconcile.py — compatibility shim for the PM-ledger reconciler.

NOT the implementation (H3-GAP-093 residual a). The single canonical reconciler lives in
the coding-hermes-scheduler repo at ops/pm-standin/ledger_board_reconcile.py, deployed at
~/.hermes/stand-in/ledger_board_reconcile.py. The duplicate implementation that used to
live here was removed so the two copies cannot drift: this shim delegates to the canonical
tool with the caller's argv unchanged and exits with the canonical tool's exit code.
"""

import os
import subprocess
import sys

CANONICAL_ENV = "LEDGER_RECONCILE_CANONICAL"
CANONICAL_SOURCE = "ops/pm-standin/ledger_board_reconcile.py (coding-hermes-scheduler repo)"
CANONICAL_DEFAULT = os.path.join("~", ".hermes", "stand-in", "ledger_board_reconcile.py")

HELP = """\
ledger-board-reconcile.py — compatibility shim, not an implementation.

1. This file is a shim: it holds no reconciliation logic and classifies nothing.
2. The single canonical implementation lives in the coding-hermes-scheduler repo at
       ops/pm-standin/ledger_board_reconcile.py
   and is deployed (symlinked) at
       ~/.hermes/stand-in/ledger_board_reconcile.py
   by ops/pm-standin/install.sh, with its suite at ops/pm-standin/test_ledger_board_reconcile.py
3. This shim accepts ONLY the canonical tool's flags. The duplicate-only flags
   --project / --all / --json were REMOVED with the duplicate implementation, so
   there is exactly one implementation and the two cannot drift.

Canonical CLI: [-h] [--apply] [--ledger LEDGER] [--scheduler-db DB] [--backup-suffix SUFFIX]

Dry run is the default (read-only); --apply writes the reconciliation. This shim resolves
the canonical tool at ~/.hermes/stand-in/ledger_board_reconcile.py (or at
$LEDGER_RECONCILE_CANONICAL when set), prints the path it resolved, passes your arguments
through unchanged, and exits with the canonical tool's exit code. When the canonical tool
is missing this shim exits 2 and names the canonical source path; it never falls back to a
local reconciliation.
"""


def canonical_path():
    """The canonical reconciler this shim delegates to (override, else ~/.hermes)."""
    override = os.environ.get(CANONICAL_ENV, "").strip()
    return os.path.expanduser(override or CANONICAL_DEFAULT)


def main(argv):
    if "-h" in argv or "--help" in argv:
        sys.stdout.write(HELP)
        return 0
    path = canonical_path()
    if not os.path.isfile(path):
        print("ledger-board-reconcile: canonical reconciler not found at %s (canonical source: "
              "%s) — this shim has no reconciliation logic of its own" % (path, CANONICAL_SOURCE),
              file=sys.stderr)
        return 2
    print("ledger-board-reconcile: DEPRECATED shim — delegating to the canonical reconciler at %s"
          % path, file=sys.stderr)
    try:
        os.execv(path, [path] + list(argv))
    except OSError as exc:  # not executable, or a broken symlink target
        print("ledger-board-reconcile: exec failed (%s) — retrying via subprocess" % exc,
              file=sys.stderr)
        return subprocess.run([sys.executable, path] + list(argv)).returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
