#!/bin/sh
# check-duckbrain-tick-chain.sh — DuckBrain tick-key shape-drift + window-hole
# checker for namespace `h3` (H3-GAP-098).
#
# WHY THIS EXISTS
#   The foreman writes one DuckBrain record per tick under the canonical bare key
#   /tick/<N>. Ticks #452 and #453 wrote theirs under DRIFTED shapes instead —
#   /project/h3/protocol/tick/452 and /project/h3/h3/tick/453 — leaving holes at
#   452 and 453 in the bare chain. Tick #459 backfilled both bare keys, but the
#   write path was never fixed and the audit's pre-write census counted ONLY bare
#   keys, so a future drift reports the chain as "contiguous" while the canonical
#   key is missing. A census that cannot see a wrong-shaped key calls a broken
#   chain whole.
#
#   This guard is the census that CAN see it: it reads the whole namespace key
#   tree (not just the bare keys), classifies every tick-ish path, and turns any
#   NEW wrong-shaped tick key into a FAILURE — so drift goes red at the gate that
#   measures it instead of being narrated as contiguous in the next audit.
#
# WHAT IT READS
#   One request: GET $H3_TICK_CHAIN_URL/api/keys?namespace=<ns>&tree&limit=<LIMIT>
#   with the X-API-Key header. Every node's "path" is collected and classified by regex:
#     canonical — ^/tick/[0-9]+$                    (the bare chain)
#     legacy    — ^/project/h3/tick/[0-9]+$ AND N <= LEGACY_MAX (427):
#                 the pre-#418 hub series 408..427, tolerated non-fatal. The class
#                 is deliberately BOUNDED — an unbounded legacy branch would
#                 silently tolerate future drifted /project/h3/tick/<N> keys
#                 (live tick-#466 specimen: bare /tick/464 missing while the
#                 drifted /project/h3/tick/464 sat in the tolerated class).
#     drift     — any OTHER path ending in /tick/<N>, N >= START (this now
#                 includes chain-A keys above LEGACY_MAX)
#     other     — tick-like paths without a bare tick number (timestamped slugs,
#                 /tick/<N>/supplement notes) — legitimate, reported, non-fatal
#   It never fetches key CONTENT: the tree endpoint is the only source
#   (/api/memories?key=... does not exact-match — measured, see H3-GAP-098).
#
# THE WINDOW
#   Required window: every integer N with START <= N <= END must have a bare
#   /tick/N key, where END = <board ticks_total> - 1. The board header's
#   ticks_total counts the tick IN FLIGHT (its DuckBrain record may not be
#   written yet), so the last tick whose record must already exist is
#   ticks_total - 1. A genuine hole at tick N is therefore caught from tick N+1
#   onward — one tick later at the latest — and never silently. The in-flight
#   tick number is reported separately as provisional, never as a hole and never
#   as an excuse: if its key is present it is still counted and printed.
#
# EXIT CODES (the convention of the sibling guards):
#   0 = VERIFIED (0 holes, 0 unknown drift) OR UNVERIFIED — the service could
#       not be reached / the answer was not readable. An unreachable state is
#       UNVERIFIED and never a PASS: zero cells is not a pass (QA-H3-1).
#   1 = FAILED — a hole in the window, an unknown drifted key, or both.
#
# Output is grep-friendly: one fact per line, ending with the verdict line
#   VERDICT: VERIFIED | UNVERIFIED (<reason>) | FAILED (<reasons>)
#
# Env overrides (all optional, defaults shown):
#   H3_TICK_CHAIN_URL=http://localhost:3000
#   H3_TICK_CHAIN_NAMESPACE=h3
#   H3_TICK_CHAIN_TOKEN_DIR=$HOME/.duckbrain      (first *.token in glob order)
#   H3_TICK_CHAIN_TREE_FILE=                      (read tree JSON from a file)
#   H3_TICK_CHAIN_TICKS_TOTAL=                    (override the board header read)
#   H3_TICK_CHAIN_START=418
#   H3_TICK_CHAIN_ALLOWLIST=452,453,464           (known twins: the #459 backfill
#                                                   plus the #466 backfill of the
#                                                   chain-A key written by tick 464)
#   H3_TICK_CHAIN_LEGACY_MAX=427                  (legacy /project/h3/tick/<N> keys
#                                                   are tolerated only up to this
#                                                   number; anything above is DRIFT)
#   H3_TICK_CHAIN_LIMIT=5000                      (api/keys page size; answer is
#                                                   UNVERIFIED when total >= limit)
#
# Dependencies: POSIX sh, jq, curl (curl only in HTTP mode), a readable token,
# and a readable board header — anything missing degrades to UNVERIFIED.
# READ ONLY: this guard never writes to DuckBrain.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

URL=${H3_TICK_CHAIN_URL:-http://localhost:3000}
URL=${URL%/}
NS=${H3_TICK_CHAIN_NAMESPACE:-h3}
TOKEN_DIR=${H3_TICK_CHAIN_TOKEN_DIR:-$HOME/.duckbrain}
TREE_FILE=${H3_TICK_CHAIN_TREE_FILE:-}
TICKS_TOTAL_OVERRIDE=${H3_TICK_CHAIN_TICKS_TOTAL:-}
START=${H3_TICK_CHAIN_START:-418}
ALLOWLIST=${H3_TICK_CHAIN_ALLOWLIST:-452,453,464}
LEGACY_MAX=${H3_TICK_CHAIN_LEGACY_MAX:-427}
LIMIT=${H3_TICK_CHAIN_LIMIT:-5000}

NAME=check-duckbrain-tick-chain
BOARD=$ROOT/.coding-hermes/board/board.jsonl

# UNVERIFIED is a first-class outcome, not a pass: it prints why and exits 0 so
# `make verify` stays runnable on a bare clone with no DuckBrain, no jq and no
# token — while never claiming the chain was checked.
unverified() {
    echo "$NAME: UNVERIFIED — $1"
    echo "VERDICT: UNVERIFIED ($1)"
    exit 0
}

case $START in
    '' | *[!0-9]*) unverified "H3_TICK_CHAIN_START is not a non-negative integer: '$START'" ;;
esac
case $LEGACY_MAX in
    '' | *[!0-9]*) unverified "H3_TICK_CHAIN_LEGACY_MAX is not a non-negative integer: '$LEGACY_MAX'" ;;
esac
case $NS in
    '' | */*) unverified "H3_TICK_CHAIN_NAMESPACE is not a bare namespace name: '$NS'" ;;
esac
case $LIMIT in
    '' | *[!0-9]*) unverified "H3_TICK_CHAIN_LIMIT is not a positive integer: '$LIMIT'" ;;
esac

command -v jq >/dev/null 2>&1 || unverified "jq not found on PATH — cannot classify the key tree"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/h3-tick-chain.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

# ---- 1. read the key tree ---------------------------------------------------
if [ -n "$TREE_FILE" ]; then
    [ -f "$TREE_FILE" ] || unverified "tree file is missing: $TREE_FILE"
    [ -r "$TREE_FILE" ] || unverified "tree file is not readable: $TREE_FILE"
    BODY=$(cat -- "$TREE_FILE") || unverified "tree file could not be read: $TREE_FILE"
    SOURCE="file:$TREE_FILE"
else
    command -v curl >/dev/null 2>&1 || unverified "curl not found on PATH — cannot reach DuckBrain"
    TOKEN_FILE=
    for f in "$TOKEN_DIR"/*.token; do
        [ -f "$f" ] || continue
        [ -r "$f" ] || continue
        TOKEN_FILE=$f
        break
    done
    [ -n "$TOKEN_FILE" ] || unverified "no readable token: no *.token file in $TOKEN_DIR"
    TOKEN=$(cat -- "$TOKEN_FILE") || unverified "token file could not be read: $TOKEN_FILE"
    [ -n "$TOKEN" ] || unverified "token file is empty: $TOKEN_FILE"
    API="$URL/api/keys?namespace=$NS&tree&limit=$LIMIT"
    BODY=$(curl -fsS -m 15 -H "X-API-Key: $TOKEN" "$API" 2>/dev/null) || BODY=
    [ -n "$BODY" ] || unverified "DuckBrain API unreachable or refused: $API"
    SOURCE="$API"
fi
unset TOKEN 2>/dev/null || true

printf '%s' "$BODY" | jq -e . >/dev/null 2>&1 || unverified "answer is not parseable JSON (source: $SOURCE)"
printf '%s' "$BODY" > "$WORK/tree.json"

# ---- 2. the board header (END basis) ---------------------------------------
if [ -n "$TICKS_TOTAL_OVERRIDE" ]; then
    TICKS_TOTAL=$TICKS_TOTAL_OVERRIDE
    TOTAL_SOURCE="H3_TICK_CHAIN_TICKS_TOTAL override"
else
    [ -f "$BOARD" ] || unverified "board header unreadable ($BOARD is missing) and no H3_TICK_CHAIN_TICKS_TOTAL override is set"
    TICKS_TOTAL=$(head -n 1 "$BOARD" 2>/dev/null | jq -r 'if type == "object" then (.ticks_total // empty) else empty end' 2>/dev/null || true)
    [ -n "$TICKS_TOTAL" ] || unverified "board header ($BOARD line 1) carries no ticks_total and no H3_TICK_CHAIN_TICKS_TOTAL override is set"
    TOTAL_SOURCE="$BOARD line 1 (ticks_total)"
fi
case $TICKS_TOTAL in
    '' | *[!0-9]*) unverified "ticks_total is not an integer: '$TICKS_TOTAL' (source: $TOTAL_SOURCE)" ;;
esac

if [ "$TICKS_TOTAL" -gt "$START" ]; then
    END=$((TICKS_TOTAL - 1))
else
    END=$START
fi
REQUIRED=$((END - START + 1))

# ---- 2b. completeness guard: the keys listing is CAPPED ---------------------
# GET /api/keys without a large enough limit silently truncates the tree, and
# the response's "total" field then counts the RETURNED nodes, not the
# namespace — so the cap is invisible in the body. Measured 2026-09-21 (h3
# tick #465): the default-capped tree read total:100 / 121 paths and reported
# bare /tick/418 as a hole that exists on disk, in the flat listing, and in
# the limit=5000 tree. A tree answer whose total reaches the limit is possibly
# truncated: degrade to UNVERIFIED, never judge a chain over a partial listing.
TOTAL_KEYS=$(jq -r 'if type == "object" then (.total // empty) else empty end' "$WORK/tree.json" 2>/dev/null || true)
case $TOTAL_KEYS in
    '' | *[!0-9]*) : ;; # total absent or non-numeric: nothing to compare, proceed
    *)
        if [ "$TOTAL_KEYS" -ge "$LIMIT" ]; then
            unverified "key-tree answer is possibly truncated (total=$TOTAL_KEYS >= limit=$LIMIT); raise H3_TICK_CHAIN_LIMIT and retry — a capped listing must never be judged"
        fi
        ;;
esac

# ---- 3. classify every tick-ish path ---------------------------------------
TAB=$(printf '\t')
jq -r --arg tab "$TAB" --arg maxn "$LEGACY_MAX" '
  [.. | .path? // empty]
  | map(
      . as $p
      | if   ($p | test("^/tick/[0-9]+$"))
        then "canonical\($tab)\(($p | capture("^/tick/(?<n>[0-9]+)$").n | tonumber))\($tab)\($p)"
        elif (($p | test("^/project/h3/tick/[0-9]+$")) and ($p | capture("^/project/h3/tick/(?<n>[0-9]+)$").n | tonumber) <= ($maxn | tonumber))
        then "legacy\($tab)\(($p | capture("^/project/h3/tick/(?<n>[0-9]+)$").n | tonumber))\($tab)\($p)"
        elif ($p | test("/tick/[0-9]+$"))
        then "driftish\($tab)\(($p | capture("/(?<n>[0-9]+)$").n | tonumber))\($tab)\($p)"
        elif ($p | test("/tick/"))
        then "other\($tab)0\($tab)\($p)"
        else "nontick\($tab)0\($tab)\($p)"
        end
    )
  | .[]
' "$WORK/tree.json" > "$WORK/classified" || unverified "could not classify the key tree (source: $SOURCE)"

: > "$WORK/canon"
: > "$WORK/legacy"
: > "$WORK/driftish"
: > "$WORK/other"
NONTICK=0
while IFS="$TAB" read -r kind n p; do
    case $kind in
        canonical) printf '%s\n' "$n" >> "$WORK/canon" ;;
        legacy)    printf '%s %s\n' "$n" "$p" >> "$WORK/legacy" ;;
        driftish)  printf '%s %s\n' "$n" "$p" >> "$WORK/driftish" ;;
        other)     printf '%s\n' "$p" >> "$WORK/other" ;;
        *)         NONTICK=$((NONTICK + 1)) ;;
    esac
done < "$WORK/classified"

sort -n -u "$WORK/canon" > "$WORK/canon_u"

# ---- 4. the window ---------------------------------------------------------
PRESENT=$(awk -v s="$START" -v e="$END" '{p[$1]=1} END{c=0; for(i=s;i<=e;i++) if(i in p) c++; print c}' "$WORK/canon_u")
awk -v s="$START" -v e="$END" '{p[$1]=1} END{for(i=s;i<=e;i++) if(!(i in p)) print i}' "$WORK/canon_u" > "$WORK/holes"
awk -v e="$END" '{p[$1]=1} END{for(i in p) if(i+0>e+0) print i+0}' "$WORK/canon_u" | sort -n > "$WORK/beyond"
awk -v s="$START" '{p[$1]=1} END{for(i in p) if(i+0<s+0) print i+0}' "$WORK/canon_u" | sort -n > "$WORK/below"
HOLES=$(wc -l < "$WORK/holes" | tr -d ' ')
BEYOND=$(wc -l < "$WORK/beyond" | tr -d ' ')
BELOW=$(wc -l < "$WORK/below" | tr -d ' ')
CANON=$(wc -l < "$WORK/canon_u" | tr -d ' ')

# ---- 5. drift: known twins vs unknown --------------------------------------
awk -v start="$START" -v allow="$ALLOWLIST" '
  BEGIN { c=split(allow, a, ","); for (i=1;i<=c;i++) { gsub(/^[ \t]+/, "", a[i]); gsub(/[ \t]+$/, "", a[i]); if (a[i] != "") ok[a[i]]=1 } }
  { n=$1+0; $1=""; sub(/^ /, "", $0)
    if (n < start) { print "below" "\t" n "\t" $0; next }
    if (n in ok) { print "known" "\t" n "\t" $0 } else { print "unknown" "\t" n "\t" $0 } }
' "$WORK/driftish" > "$WORK/drift_classified"
DRIFT_KNOWN=$(grep -c '^known' "$WORK/drift_classified" || true)
DRIFT_UNKNOWN=$(grep -c '^unknown' "$WORK/drift_classified" || true)
DRIFT_BELOW=$(grep -c '^below' "$WORK/drift_classified" || true)

# ---- 6. report: one fact per line ------------------------------------------
echo "$NAME: namespace=$NS start=$START source=$SOURCE"
echo "tick-chain: tree-paths total=$(wc -l < "$WORK/classified" | tr -d ' ') canonical=$CANON legacy=$(wc -l < "$WORK/legacy" | tr -d ' ') drift-known=$DRIFT_KNOWN drift-unknown=$DRIFT_UNKNOWN other=$(wc -l < "$WORK/other" | tr -d ' ')"
echo "tick-chain: window $START..$END (required, $REQUIRED ticks)"
echo "tick-chain: window-basis END=$END = ticks_total $TICKS_TOTAL - 1 (source: $TOTAL_SOURCE); the header counts the in-flight tick, whose record may not be written yet"
echo "tick-chain: window-present $PRESENT/$REQUIRED"
echo "tick-chain: holes $HOLES"
while read -r h; do
    [ -n "$h" ] && echo "tick-chain: hole $h (/tick/$h missing)"
done < "$WORK/holes"
echo "tick-chain: beyond-end $BEYOND (canonical keys above the required END; the in-flight tick is not required until the next tick)"
while read -r b; do
    [ -n "$b" ] && echo "tick-chain: beyond-end-key $b (/tick/$b present, in flight)"
done < "$WORK/beyond"

LEGACY_RANGE="-"
if [ -s "$WORK/legacy" ]; then
    LEGACY_MIN=$(awk '{print $1}' "$WORK/legacy" | sort -n | head -n 1 | tr -d ' ')
    LEGACY_LAST=$(awk '{print $1}' "$WORK/legacy" | sort -n | tail -n 1 | tr -d ' ')
    LEGACY_RANGE="/project/h3/tick/$LEGACY_MIN../project/h3/tick/$LEGACY_LAST"
fi
echo "tick-chain: legacy $LEGACY_RANGE ($(wc -l < "$WORK/legacy" | tr -d ' ') keys, pre-#418 hub convention — tolerated, non-fatal, bounded <= LEGACY_MAX=$LEGACY_MAX)"
echo "tick-chain: drift-known $DRIFT_KNOWN (allowlist $ALLOWLIST — #459 backfill twins 452/453 + the #466-backfilled chain-A key 464)"
while IFS="$TAB" read -r k n p; do
    [ -n "${p:-}" ] || continue
    [ "$k" = "known" ] || continue
    echo "tick-chain: drift-known-key $n $p"
done < "$WORK/drift_classified"
echo "tick-chain: drift-unknown $DRIFT_UNKNOWN"
while IFS="$TAB" read -r k n p; do
    [ -n "${p:-}" ] || continue
    [ "$k" = "unknown" ] || continue
    echo "tick-chain: drift-unknown-key $n $p"
done < "$WORK/drift_classified"
echo "tick-chain: drift-below-start $DRIFT_BELOW (wrong-shaped keys below START=$START — outside the window, non-fatal)"
echo "tick-chain: other $(wc -l < "$WORK/other" | tr -d ' ') (tick-like keys without a bare tick number — timestamped slugs / supplement notes; non-fatal)"
while read -r o; do
    [ -n "$o" ] && echo "tick-chain: other-key $o"
done < "$WORK/other"
echo "tick-chain: sparse-below-start $BELOW (bare keys older than START=$START — outside the window, non-fatal)"
while read -r s; do
    [ -n "$s" ] && echo "tick-chain: sparse-below-start-key $s"
done < "$WORK/below"

# ---- 7. verdict ------------------------------------------------------------
if [ "$HOLES" -eq 0 ] && [ "$DRIFT_UNKNOWN" -eq 0 ]; then
    echo "$NAME: PASS — the bare chain $START..$END is complete and no unknown-shaped tick key exists (source: $SOURCE)"
    echo "VERDICT: VERIFIED (0 holes in $START..$END; 0 unknown drift keys; $DRIFT_KNOWN allowlisted known twin(s))"
    exit 0
fi

REASONS=
if [ "$HOLES" -gt 0 ]; then
    REASONS="$HOLES hole(s): $(tr '\n' ' ' < "$WORK/holes" | sed 's/ $//')"
fi
if [ "$DRIFT_UNKNOWN" -gt 0 ]; then
    UNKNOWN_KEYS=$(awk -F"$TAB" '$1 == "unknown" {print $3}' "$WORK/drift_classified" | tr '\n' ' ' | sed 's/ $//')
    [ -n "$REASONS" ] && REASONS="$REASONS; "
    REASONS="${REASONS}$DRIFT_UNKNOWN unknown drift key(s): $UNKNOWN_KEYS"
fi
echo "$NAME: FAIL — $REASONS (source: $SOURCE)"
echo "VERDICT: FAILED ($REASONS)"
exit 1
