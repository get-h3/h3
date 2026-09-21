#!/bin/sh
# duckbrain-tick-record.sh — the CANONICAL writer for namespace-h3 tick records
# (DF-H3-23). Tick #464's foreman hand-rolled its record POST and drifted the
# key to /project/h3/tick/464 while verifying presence with a content grep that
# was blind to key shape — the same writer bug that hit ticks #452/#453 before
# the #459 backfill. The census (check-duckbrain-tick-chain.sh) catches the
# hole one tick later; THIS tool exists so the write is right the first time.
#
# What it does:
#   duckbrain-tick-record.sh <N>                     # POST bare /tick/<N> from
#                                                    # stdin (or --content-file)
#   duckbrain-tick-record.sh <N> --content-file F    # POST bare /tick/<N> with
#                                                    # the raw text of file F
#   duckbrain-tick-record.sh <N> --check-only        # no POST: re-GET and
#                                                    # assert the exact bare key
#
# The WRITE-side regression check (DF-H3-23's third ask) is built in: after
# every write (and in --check-only mode) the tool re-GETs prefix=/tick/<N> and
# FAILS unless exactly one item comes back AND that item's key is exactly
# /tick/<N> — a content grep under a drifted key does not pass here.
#
# Env overrides (defaults match check-duckbrain-tick-chain.sh):
#   H3_TICK_CHAIN_URL=http://localhost:3000
#   H3_TICK_CHAIN_NAMESPACE=h3
#   H3_TICK_CHAIN_TOKEN_DIR=$HOME/.duckbrain      (first *.token in glob order)
#
# Exit codes: 0 = written+verified or checked+verified; 1 = shape mismatch or
# refused write; 2 = bad usage; UNVERIFIED degradation (no jq/curl/token, API
# unreachable) prints the reason and exits 0 like the census — absent tooling
# is UNVERIFIED, never a pass. WRITE scope: exactly one record per invocation;
# --check-only is read-only.
#
# Dependencies: POSIX sh, jq, curl. domain=event per the h3 namespace contract
# (`foreman` is rejected by the API's domain enum).

set -eu

NAME=duckbrain-tick-record
URL=${H3_TICK_CHAIN_URL:-http://localhost:3000}
URL=${URL%/}
NS=${H3_TICK_CHAIN_NAMESPACE:-h3}
TOKEN_DIR=${H3_TICK_CHAIN_TOKEN_DIR:-$HOME/.duckbrain}

usage() {
    echo "usage: $NAME <tick-number> [--content-file F | --check-only]" >&2
    echo "  content defaults to stdin; --check-only re-GETs and asserts the bare key" >&2
}

N=${1:-}
[ -n "$N" ] || { usage; exit 2; }
case $N in
    '' | *[!0-9]*) echo "$NAME: tick number is not a non-negative integer: '$N'" >&2; exit 2 ;;
esac
shift
CONTENT_FILE=
CHECK_ONLY=0
while [ $# -gt 0 ]; do
    case $1 in
        --content-file) CONTENT_FILE=${2:-}; [ -n "$CONTENT_FILE" ] || { usage; exit 2; }; shift 2 ;;
        --check-only)   CHECK_ONLY=1; shift ;;
        *)              usage; exit 2 ;;
    esac
done

unverified() {
    echo "$NAME: UNVERIFIED — $1"
    exit 0
}

command -v jq >/dev/null 2>&1 || unverified "jq not found on PATH"
command -v curl >/dev/null 2>&1 || unverified "curl not found on PATH"

TOKEN_FILE=
for f in "$TOKEN_DIR"/*.token; do
    [ -f "$f" ] || continue
    [ -r "$f" ] || continue
    TOKEN_FILE=$f
    break
done
[ -n "$TOKEN_FILE" ] || unverified "no readable token: no *.token file in $TOKEN_DIR"
TOKEN=$(cat -- "$TOKEN_FILE") || unverified "token file could not be read"
[ -n "$TOKEN" ] || unverified "token file is empty"

if [ "$CHECK_ONLY" -eq 0 ]; then
    if [ -n "$CONTENT_FILE" ]; then
        [ -f "$CONTENT_FILE" ] || { echo "$NAME: content file missing: $CONTENT_FILE" >&2; exit 2; }
        [ -r "$CONTENT_FILE" ] || { echo "$NAME: content file not readable: $CONTENT_FILE" >&2; exit 2; }
        BODY=$(jq -n --arg k "/tick/$N" --arg d event --rawfile c "$CONTENT_FILE" \
            '{key: $k, domain: $d, content: $c}')
    else
        BODY=$(jq -n --arg k "/tick/$N" --arg d event --rawfile c /dev/stdin \
            '{key: $k, domain: $d, content: $c}')
    fi
    [ -n "$BODY" ] || { echo "$NAME: refused: empty payload (an empty write must fail loudly)" >&2; exit 1; }
    API="$URL/api/memories?namespace=$NS"
    RESP=$(printf '%s' "$BODY" | curl -fsS -m 15 -X POST -H "X-API-Key: $TOKEN" \
        -H "Content-Type: application/json" -d @- "$API" 2>/dev/null) || \
        unverified "DuckBrain API unreachable or refused the write: $API"
    printf '%s' "$RESP" | jq -e . >/dev/null 2>&1 || unverified "write response is not parseable JSON"
    echo "$NAME: POSTed namespace=$NS key=/tick/$N id=$(printf '%s' "$RESP" | jq -r '.id // empty')"
fi

# ---- the write-side regression check: exact bare key, exactly one item -------
QAPI="$URL/api/memories?namespace=$NS&prefix=%2Ftick%2F$N&limit=100"
GOT=$(curl -fsS -m 15 -H "X-API-Key: $TOKEN" "$QAPI" 2>/dev/null) || \
    unverified "DuckBrain API unreachable or refused the read: $QAPI"
printf '%s' "$GOT" | jq -e . >/dev/null 2>&1 || unverified "read response is not parseable JSON"
COUNT=$(printf '%s' "$GOT" | jq '.items | length')
KEYS=$(printf '%s' "$GOT" | jq -r '[.items[].key] | join(",")')
if [ "$COUNT" -eq 1 ] && [ "$KEYS" = "/tick/$N" ]; then
    echo "$NAME: VERIFIED — /tick/$N present with the exact canonical key (1 item)"
    exit 0
fi
echo "$NAME: FAIL — expected exactly one item at the bare key /tick/$N; got count=$COUNT keys=$KEYS"
exit 1
