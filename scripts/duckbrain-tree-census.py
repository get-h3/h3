#!/usr/bin/env python3
"""duckbrain-tree-census.py — independent DuckBrain key-tree census walker.

WHY THIS EXISTS (H3-GAP-099)
    The NEVER-DONE audit's DuckBrain tick-chain census was an ad-hoc script kept
    in /tmp (79th audit, tick #469, and 80th audit, tick #474, both ran it and
    both recorded the same census_tool_note: "ad-hoc /tmp walker; NOT committed").
    /tmp evaporates on reboot, so a recurring audit step depended on a file that
    no clone carries. This is that walker, promoted into the repo, still
    deliberately DUPLICATING the classification logic of the sibling guard
    scripts/check-duckbrain-tick-chain.sh (H3-GAP-098) instead of importing it:
    the audit census is only worth publishing because it is an INDEPENDENT
    second reader of the same tree. Two implementations that disagree are the
    signal; one implementation calling itself twice is not.

    Provenance: promoted from the audits' /tmp/h3-duckbrain-census.py (ticks
    #469 / #474). The tree-walk shape is unchanged — collect every node's "id"
    and "path" attribute, recurse into "children", match /tick/<N> against the
    leaf paths — so the numbers it prints stay comparable with the audits'.

WHAT IT READS
    One read-only request: GET <url>/api/keys?namespace=<ns>&tree&limit=<limit>
    with the X-API-Key header, or a pre-fetched tree JSON via --tree-file
    (offline mode — the repos' checks and their selftests use this). It is the
    same source the sibling guard uses; no key CONTENT is ever fetched
    (/api/memories does not exact-match, see H3-GAP-098).

    It classifies every tick-ish path:
      bare   — ^/tick/<N>$                        the canonical chain
      legacy — ^/project/<ns>/tick/<N>$ with N <= LEGACY_MAX (427):
               the pre-#418 hub series, tolerated, non-fatal, BOUNDED (an
               unbounded legacy branch would silently tolerate future drifted
               /project/h3/tick/<N> keys — the live #466 specimen).
      drift  — any OTHER path ending in /tick/<N> with N >= start, UNLESS N is in
               the known allowlist (default 452,453,464 — the sibling guard's
               H3_TICK_CHAIN_ALLOWLIST). Those three are wrong-shaped keys the
               live namespace already carries and ticks #459/#466 already
               backfilled; they are reported as `drift-known` and tolerated. The
               list is not cosmetic: without it every live run goes red for keys
               that are already repaired, which is why the guard carries it too.
      other  — tick-like paths with no bare tick number (timestamped slugs,
               /tick/<N>/supplement notes) — legitimate, non-fatal.

USAGE
    python3 scripts/duckbrain-tree-census.py h3 --start 418 --end 474
    python3 scripts/duckbrain-tree-census.py h3 --start 418 --end 474 \\
        --tree-file /tmp/h3keys.json          # offline, no network
    python3 scripts/duckbrain-tree-census.py h3 --start 418 --end auto
        # 'auto' (alias 'board'): END = board ticks_total - 1, the sibling
        # guard's window basis — the header counts the tick IN FLIGHT, whose
        # record may not be written yet, so the last required record is
        # ticks_total - 1. This is the mode `make verify-tick-chain` uses.
    printenv H3OPS_DUCKBRAIN_API_KEY | wc -c      # the token env it reads

    Options: --start N (default 418), --end N | auto | board (omitted = EMPTY
    window start..start-1: the hole check is skipped, the drift census still
    runs — a caller that wants a closed window must say so), --tree-file PATH,
    --url URL (default https://duckbrain.dexdat.com), --token-env NAME
    (default H3OPS_DUCKBRAIN_API_KEY), --token-file PATH (explicit opt-in
    alternative for ad-hoc runs; there is NO silent fallback to a token file),
    --limit N (default 20000), --legacy-max N (default 427), --allowlist N,...
    (default 452,453,464; pass '' for the raw drift class), --board PATH,
    --ticks-total N (override the board read).

OUTPUT
    One fact per line, plus the audit-publishable census line
        present=<N> missing=[..] unknown_drift=[..]
    present counts bare /tick/N keys inside the window, missing lists the
    absent window integers, unknown_drift lists the N of every wrong-shaped
    tick key at N >= start (their paths are printed on their own lines). The
    totals line ("total leaf keys: ... | tick-shaped keys: ...") is kept in the
    audits' wording.

UNVERIFIED SEMANTICS (the repo's gate philosophy, Makefile header)
    An unreadable substrate is UNVERIFIED, never a PASS and never a FAIL: zero
    cells is not a pass (QA-H3-1). This script exits 0 with an audible
        UNVERIFIED — <reason>
    line when the token env var is unset (and no --token-file was given), the
    fetch fails (urllib error / non-2xx / unparseable JSON), the answer is
    possibly truncated (total >= limit), the tree file is missing/unreadable/
    unparseable, or the board header is unreadable in --end auto mode. Exit 1
    is reserved for a census that actually READ the tree and found holes or
    unknown drift.

EXIT CODES
    0 = VERIFIED (0 holes, 0 unknown drift) or UNVERIFIED
    1 = FAILED (a hole in the window and/or an unknown-shaped tick key)
    2 = usage error (argparse)

STDLIB ONLY: argparse, json, os, re, sys, urllib. No jq, no third-party code.
READ ONLY: this script never writes to DuckBrain.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request

NAME = "duckbrain-tree-census"
DEFAULT_START = 418
DEFAULT_LEGACY_MAX = 427
DEFAULT_URL = "https://duckbrain.dexdat.com"
DEFAULT_TOKEN_ENV = "H3OPS_DUCKBRAIN_API_KEY"
DEFAULT_LIMIT = 20000
# Known wrong-shaped tick numbers, mirrored from the sibling guard's default
# (check-duckbrain-tick-chain.sh: H3_TICK_CHAIN_ALLOWLIST=452,453,464). They are
# the #459-backfilled twins (452/453) plus the #466-backfilled chain-A key 464 —
# keys that already exist in the live namespace, written before the canonical
# bare chain was the rule. They are TOLERATED and reported as `drift-known`, so
# the live census agrees with the guard instead of calling the whole chain red
# for three keys two ticks already backfilled. Pass --allowlist '' for the raw
# classification.
DEFAULT_ALLOWLIST = "452,453,464"

# Any tick-shaped path: the tallies line counts these (same regex as the
# promoted /tmp walker's `(?:^|/)tick/(\d+)$`).
TICKISH = re.compile(r"(?:^|/)tick/(\d+)$")
# The canonical bare chain — exactly /tick/<digits>, nothing around it.
BARE = re.compile(r"^/tick/(\d+)$")
# Tick-like but without a bare tick number (timestamped slugs, /tick/N/notes).
TICKLIKE = re.compile(r"/tick/")


def unverified(reason: str) -> int:
    """Unreadable substrate: say why, exit 0. Never a PASS over an unread tree."""
    print("%s: UNVERIFIED — %s" % (NAME, reason))
    print("VERDICT: UNVERIFIED (%s)" % reason)
    return 0


def repo_root() -> str:
    return os.path.dirname(os.path.dirname(os.path.realpath(__file__)))


def read_ticks_total(board_path: str):
    """Board header -> (ticks_total:int|None, source:str).

    The board header is a one-line object; ticks_total counts the tick in
    flight, so a window END derived from it is ticks_total - 1 (the sibling
    guard's basis). An unreadable/non-integer header is reported as-is: the
    caller turns that into UNVERIFIED.
    """
    if not os.path.isfile(board_path):
        return None, "board header unreadable (%s is missing)" % board_path
    try:
        with open(board_path, "r", encoding="utf-8", errors="replace") as fh:
            first = fh.readline()
    except OSError as exc:
        return None, "board header unreadable (%s: %s)" % (board_path, exc)
    try:
        header = json.loads(first)
    except ValueError:
        return None, "board header (%s line 1) is not JSON" % board_path
    if not isinstance(header, dict):
        return None, "board header (%s line 1) is not an object" % board_path
    total = header.get("ticks_total")
    if isinstance(total, bool) or not isinstance(total, int):
        return None, (
            "board header (%s line 1) carries no integer ticks_total" % board_path
        )
    return total, "%s line 1 (ticks_total=%d)" % (board_path, total)


def walk_keys(node, out):
    """Collect every node's "id"/"path" strings, recursing into "children".

    Same shape as the promoted /tmp walker (its `walk()`), made defensive: a
    malformed child that is not an object is skipped rather than crashing a
    census whose whole job is to still report the rest of the tree.
    """
    if not isinstance(node, dict):
        return
    for attr in ("id", "path"):
        value = node.get(attr)
        if isinstance(value, str):
            out.append(value)
    children = node.get("children")
    if isinstance(children, list):
        for child in children:
            walk_keys(child, out)


def load_tree(args):
    """-> (body_text, source, error_reason). error_reason set means UNVERIFIED."""
    if args.tree_file:
        path = args.tree_file
        if not os.path.isfile(path):
            return None, "file:%s" % path, "tree file is missing: %s" % path
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                return fh.read(), "file:%s" % path, None
        except OSError as exc:
            return None, "file:%s" % path, "tree file could not be read (%s: %s)" % (
                path,
                exc,
            )

    url = args.url.rstrip("/")
    token = os.environ.get(args.token_env, "")
    if not token:
        if args.token_file:
            if not os.path.isfile(args.token_file):
                return (
                    None,
                    "file:%s" % args.token_file,
                    "token file is missing: %s" % args.token_file,
                )
            try:
                with open(args.token_file, "r", encoding="utf-8", errors="replace") as fh:
                    token = fh.read().strip()
            except OSError as exc:
                return None, "file:%s" % args.token_file, (
                    "token file could not be read (%s: %s)" % (args.token_file, exc)
                )
            if not token:
                return None, "file:%s" % args.token_file, (
                    "token file is empty: %s" % args.token_file
                )
        else:
            return (
                None,
                url,
                "token env var is unset or empty: %s — set it, or pass "
                "--token-file PATH, or use --tree-file PATH for an offline census"
                % args.token_env,
            )

    api = "%s/api/keys?namespace=%s&tree&limit=%d" % (url, args.namespace, args.limit)
    request = urllib.request.Request(api, headers={"X-API-Key": token})
    try:
        with urllib.request.urlopen(request, timeout=args.timeout) as response:
            code = getattr(response, "status", 200)
            body = response.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        return None, api, "DuckBrain API returned HTTP %s: %s" % (exc.code, api)
    except (urllib.error.URLError, OSError, ValueError) as exc:
        return None, api, "DuckBrain API unreachable or refused (%s): %s" % (exc, api)
    if code < 200 or code >= 300:
        return None, api, "DuckBrain API returned HTTP %s: %s" % (code, api)
    if not body.strip():
        return None, api, "DuckBrain API returned an empty body: %s" % api
    return body, api, None


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        prog=NAME,
        description=(
            "DuckBrain key-tree census: bare /tick/<N> chain completeness in a "
            "window, plus wrong-shaped tick keys (drift) at N >= start."
        ),
    )
    parser.add_argument("namespace", help="DuckBrain namespace, e.g. h3")
    parser.add_argument(
        "--start",
        type=int,
        default=DEFAULT_START,
        help="first tick number of the chain (default: %d)" % DEFAULT_START,
    )
    parser.add_argument(
        "--end",
        default=None,
        help=(
            "last tick number of the closed window, or 'auto'/'board' to derive "
            "END = board ticks_total - 1. Omitted: EMPTY window start..start-1 "
            "(no hole check; the drift census still runs)."
        ),
    )
    parser.add_argument(
        "--tree-file",
        default=None,
        help="offline mode: read a pre-fetched tree JSON instead of calling the API",
    )
    parser.add_argument("--url", default=DEFAULT_URL, help="DuckBrain base URL")
    parser.add_argument(
        "--token-env",
        default=DEFAULT_TOKEN_ENV,
        help="env var holding the API token (default: %s)" % DEFAULT_TOKEN_ENV,
    )
    parser.add_argument(
        "--token-file",
        default=None,
        help=(
            "explicit alternative token source (used only when --token-env is "
            "unset; there is no silent fallback — an absent token stays UNVERIFIED)"
        ),
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=DEFAULT_LIMIT,
        help="api/keys page size (default: %d)" % DEFAULT_LIMIT,
    )
    parser.add_argument(
        "--legacy-max",
        type=int,
        default=DEFAULT_LEGACY_MAX,
        help=(
            "legacy /project/<ns>/tick/<N> keys are tolerated only up to this N; "
            "anything above is drift (default: %d)" % DEFAULT_LEGACY_MAX
        ),
    )
    parser.add_argument(
        "--allowlist",
        default=DEFAULT_ALLOWLIST,
        help=(
            "comma-separated KNOWN wrong-shaped tick numbers, tolerated and "
            "reported (default: %s — the sibling guard's known-twin list: the "
            "452/453 backfill twins plus the #466-backfilled chain-A key 464). "
            "Pass --allowlist '' to see the raw drift class."
            % DEFAULT_ALLOWLIST
        ),
    )
    parser.add_argument(
        "--board",
        default=os.path.join(repo_root(), ".coding-hermes", "board", "board.jsonl"),
        help="board JSONL whose line 1 carries ticks_total (for --end auto)",
    )
    parser.add_argument(
        "--ticks-total",
        type=int,
        default=None,
        help="override the board read when resolving --end auto",
    )
    parser.add_argument("--timeout", type=float, default=15.0, help="HTTP timeout seconds")
    args = parser.parse_args(argv)

    if args.start < 0:
        return unverified("--start is negative: %d" % args.start)
    if args.legacy_max < 0:
        return unverified("--legacy-max is negative: %d" % args.legacy_max)
    if args.limit < 1:
        return unverified("--limit is not positive: %d" % args.limit)

    # ---- resolve the window -------------------------------------------------
    end_mode = "closed"
    window_basis = "(--end %s)" % args.end if args.end is not None else ""
    if args.end is None:
        end = args.start - 1  # EMPTY window: no hole check, drift census only
        end_mode = "empty"
        window_basis = "no --end given: EMPTY window (hole check skipped)"
    elif str(args.end).lower() in ("auto", "board"):
        if args.ticks_total is not None:
            total = args.ticks_total
            total_source = "--ticks-total override"
        else:
            total, total_source = read_ticks_total(args.board)
            if total is None:
                return unverified(
                    "%s and no --ticks-total override — cannot resolve --end auto"
                    % total_source
                )
        if total > args.start:
            end = total - 1
        else:
            end = args.start
        window_basis = (
            "END=%d = ticks_total %d - 1 (source: %s); the header counts the "
            "in-flight tick, whose record may not be written yet" % (end, total, total_source)
        )
    else:
        try:
            end = int(str(args.end))
        except ValueError:
            return unverified(
                "--end is neither an integer nor 'auto'/'board': %r" % args.end
            )

    # ---- read the tree ------------------------------------------------------
    body, source, error = load_tree(args)
    if error:
        return unverified(error)
    try:
        document = json.loads(body)
    except ValueError as exc:
        return unverified("answer is not parseable JSON (%s) (source: %s)" % (exc, source))
    if not isinstance(document, dict) or not isinstance(document.get("tree"), list):
        return unverified(
            "answer carries no top-level 'tree' list (source: %s)" % source
        )

    # A capped listing silently omits keys (measured 2026-09-21: a default-capped
    # tree reported bare /tick/418 as a hole that exists). Never judge a partial
    # listing — the same guard the sibling checker carries.
    total_keys_field = document.get("total")
    if isinstance(total_keys_field, int) and not isinstance(total_keys_field, bool):
        if total_keys_field >= args.limit:
            return unverified(
                "key-tree answer is possibly truncated (total=%d >= limit=%d); "
                "raise --limit and retry — a capped listing must never be judged"
                % (total_keys_field, args.limit)
            )

    # ---- classify -----------------------------------------------------------
    keys: list[str] = []
    for node in document["tree"]:
        walk_keys(node, keys)

    bare: set[int] = set()
    bare_paths: dict[int, str] = {}
    tickish: set[int] = set()
    legacy: set[int] = set()
    drift: dict[int, list[str]] = {}
    known_drift: dict[int, list[str]] = {}
    other: list[str] = []
    legacy_re = re.compile(r"^/project/%s/tick/(\d+)$" % re.escape(args.namespace))
    allow = set()
    for item in str(args.allowlist).split(","):
        item = item.strip()
        if item:
            try:
                allow.add(int(item))
            except ValueError:
                return unverified("--allowlist entry is not an integer: %r" % item)

    # `keys` deliberately keeps the id+path duplication (the totals line is kept
    # in the audits' wording), but classification runs over the distinct set: a
    # node carrying both attributes is one key, not two, and a duplicated drift
    # path must not be reported twice.
    for path in sorted(set(keys)):
        match = TICKISH.search(path)
        if match:
            tickish.add(int(match.group(1)))
        bare_match = BARE.match(path)
        if bare_match:
            n = int(bare_match.group(1))
            bare.add(n)
            bare_paths.setdefault(n, path)
            continue
        if not match:
            if TICKLIKE.search(path):
                other.append(path)
            continue
        n = int(match.group(1))
        legacy_match = legacy_re.match(path)
        if legacy_match and n <= args.legacy_max:
            legacy.add(n)
            continue
        if n < args.start:
            continue  # wrong-shaped below the window: outside the census, non-fatal
        if n in allow:
            known_drift.setdefault(n, []).append(path)
        else:
            drift.setdefault(n, []).append(path)
    other = sorted(set(other))

    present = sorted(n for n in bare if args.start <= n <= end)
    missing = [n for n in range(args.start, end + 1) if n not in bare]
    drift_ns = sorted(drift)
    known_ns = sorted(known_drift)
    beyond_end = len([n for n in bare if n > end])

    # ---- report -------------------------------------------------------------
    print(
        "%s: namespace=%s start=%d source=%s" % (NAME, args.namespace, args.start, source)
    )
    print("total leaf keys: %d | tick-shaped keys: %d" % (len(keys), len(tickish)))
    if end_mode == "empty":
        print(
            "window %d..%d (required 0; %s)"
            % (args.start, end, window_basis)
        )
    else:
        print(
            "window %d..%d (required %d; %s)"
            % (args.start, end, end - args.start + 1, window_basis)
        )
    print(
        "present=%d missing=[%s] unknown_drift=[%s]"
        % (
            len(present),
            ",".join(str(n) for n in missing),
            ",".join(str(n) for n in drift_ns),
        )
    )
    for n in missing:
        print("%s: hole %d (/tick/%d missing)" % (NAME, n, n))
    for n in drift_ns:
        for path in sorted(drift[n]):
            print("%s: drift-key %d %s" % (NAME, n, path))
    print(
        "%s: drift-known %d (allowlist %s — wrong-shaped but already backfilled, "
        "tolerated, non-fatal; the sibling guard carries the same list)"
        % (NAME, len(known_ns), args.allowlist or "-")
    )
    for n in known_ns:
        for path in sorted(known_drift[n]):
            print("%s: drift-known-key %d %s" % (NAME, n, path))
    print(
        "%s: legacy %d keys (/project/%s/tick/<N> with N <= %d — tolerated, "
        "non-fatal, bounded)"
        % (NAME, len(legacy), args.namespace, args.legacy_max)
    )
    print(
        "%s: other %d (tick-like keys with no bare tick number — timestamped "
        "slugs / supplement notes; non-fatal)" % (NAME, len(other))
    )
    for path in other:
        print("%s: other-key %s" % (NAME, path))
    if end_mode != "empty":
        print(
            "%s: beyond-end %d (bare keys above END=%d — the in-flight tick is "
            "not required until the next tick)" % (NAME, beyond_end, end)
        )

    # ---- verdict ------------------------------------------------------------
    if not missing and not drift_ns:
        print(
            "%s: PASS — the bare chain %d..%d is complete and no unknown-shaped "
            "tick key exists (source: %s)" % (NAME, args.start, end, source)
        )
        print(
            "VERDICT: VERIFIED (%d hole(s) in %d..%d; 0 unknown drift keys; "
            "%d allowlisted known drift key(s))"
            % (len(missing), args.start, end, len(known_ns))
        )
        return 0

    reasons = []
    if missing:
        reasons.append(
            "%d hole(s): %s" % (len(missing), " ".join(str(n) for n in missing))
        )
    if drift_ns:
        drifted = [p for n in drift_ns for p in sorted(drift[n])]
        reasons.append(
            "%d unknown drift key(s): %s" % (len(drift_ns), " ".join(drifted))
        )
    joined = "; ".join(reasons)
    print("%s: FAIL — %s (source: %s)" % (NAME, joined, source))
    print("VERDICT: FAILED (%s)" % joined)
    return 1


if __name__ == "__main__":
    sys.exit(main())
