#!/usr/bin/env bash
# QA-H3-29 controlled ordering proof — proves ORDERING, not a full battery.
#
# What this does (and only this):
#  * Takes the FIX 3 node+npm bootstrap block VERBATIM from the live
#    /home/kara/.hermes/scripts/bunker-qa.sh (lines 3426-3440, post-move) into
#    fix3-verbatim.sh, then unescapes `\$` -> `$` — byte-for-byte the same
#    transformation the harness's own UNQUOTED heredoc (bunker-qa.sh line 1971,
#    `cat <<EOF`) performs when it ships the block into the agent's qa-run.sh.
#    fix3-adapted.sh is therefore exactly what the agent executes.
#  * Harness adaptations ONLY, outside the block: `cell()` is stubbed to echo
#    (it is the grading sink, not the mechanism under test) and LOGD is set to
#    a scratch dir; `curl` is stubbed on PATH to serve a pre-built fake node
#    tarball so the proof is controlled (no real download, deterministic).
#  * PATH is scrubbed of node: PATH="$SCRUBBED_PATH" with a FRESH HOME per
#    run so ~/tools cannot pre-exist. The "tests cell" stand-in is `command -v
#    npm` — exactly the precondition h3's `make verify-roundtrip` needs when it
#    shells out to npm.
#  * OLD order: tests cell runs BEFORE the bootstrap  -> npm missing -> rc=2.
#    NEW order: bootstrap runs BEFORE the tests cell  -> npm found   -> rc=0.
set -u
P=/tmp/qa-h3-29-proof
STUB="$P/stub"
LOGD="$P/logs"
export LOGD

# -- fixture: fake node+npm tree, real shell-script npm so `command -v npm` works
FIXTREE="$P/fake-node/node-v22.15.0-linux-x64"
mkdir -p "$FIXTREE/bin"
printf 'ELF-fake\n' > "$FIXTREE/bin/node"            # ELF magic check only (head -c 4)
printf '#!/bin/sh\necho v22.15.0-fake\n' > "$FIXTREE/bin/npm"
chmod +x "$FIXTREE/bin/npm"
tar -cJf "$P/fake-node.tar.xz" -C "$P/fake-node" node-v22.15.0-linux-x64

# -- stub curl: "download" = copy the fixture (controlled, no network)
cat > "$STUB/curl" <<'EOS'
#!/bin/sh
out=""
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2;; *) shift;; esac; done
cp /tmp/qa-h3-29-proof/fake-node.tar.xz "$out"
EOS
chmod +x "$STUB/curl"

# -- scrubbed PATH: this HOST ships /usr/bin/node, so a node-free PATH must
#    exclude that dir. Build a dedicated bin dir mirroring /usr/bin + /bin
#    EXCEPT node/npm/npx/nodejs, with the stub curl first.
SCRUB="$P/scrubbin"
mkdir -p "$SCRUB"
for f in /usr/bin/* /bin/*; do
  b=$(basename "$f")
  case "$b" in node|npm|npx|nodejs) continue;; esac
  [ -e "$SCRUB/$b" ] || ln -s "$f" "$SCRUB/$b" 2>/dev/null || true
done
ln -sf "$STUB/curl" "$SCRUB/curl"
export SCRUBBED_PATH="$SCRUB:$STUB"
# verify the scrubbed PATH is truly node-free but keeps the tools the block needs
( export PATH="$SCRUBBED_PATH"; hash -r
  if command -v node >/dev/null 2>&1 || command -v npm >/dev/null 2>&1; then exit 1; fi
  command -v curl >/dev/null 2>&1 || exit 2
  command -v tar  >/dev/null 2>&1 || exit 2 ) || {
  echo "FATAL: scrubbed PATH invalid (node present or curl/tar missing)" >&2; exit 3
}

# -- grading-sink stub (NOT part of the block)
cell() { echo "  [cell] toolchain-bootstrap $1: $2"; }

run_tests_cell() {  # native-suite tests cell stand-in
  if command -v npm >/dev/null 2>&1; then echo "  tests-cell: npm FOUND (rc=0)"; return 0
  else echo "  tests-cell: npm: command not found (rc=2)"; return 2; fi
}

echo "=== OLD ordering (bootstrap AFTER tests cell — the QA-H3-29 bug) ==="
run_old() { (
  set -u
  export HOME="$1" PATH="$SCRUBBED_PATH"
  hash -r
  run_tests_cell; tests_rc=$?
  source "$P/fix3-adapted.sh"
  echo "  tests_rc=$tests_rc   (bootstrap ran AFTER the tests cell)"
  [ "$tests_rc" -eq 0 ]
); }
run_old "$P/home-old" && old_rc=0 || old_rc=$?

echo
echo "=== NEW ordering (bootstrap BEFORE tests cell — the QA-H3-29 fix) ==="
run_new() { (
  set -u
  export HOME="$1" PATH="$SCRUBBED_PATH"
  hash -r
  source "$P/fix3-adapted.sh"
  run_tests_cell; tests_rc=$?
  echo "  tests_rc=$tests_rc   node=$(command -v node 2>/dev/null || echo ABSENT)"
  [ "$tests_rc" -eq 0 ]
); }
run_new "$P/home-new" && new_rc=0 || new_rc=$?

echo
echo "=== ASSERTIONS ==="
if [ "$new_rc" -eq 0 ]; then echo "ASSERT1 PASS: NEW order — PATH gains \$HOME/tools/node/bin BEFORE the tests cell runs (npm found, rc=0)"
else echo "ASSERT1 FAIL: NEW order tests cell rc=$new_rc"; fi
if [ "$old_rc" -ne 0 ]; then echo "ASSERT2 PASS: OLD order — tests cell fails 'npm: command not found' (rc=2) — reproduces the false-FAIL arm"
else echo "ASSERT2 FAIL: OLD order unexpectedly passed (rc=$old_rc) — fixture invalid"; fi
if [ "$new_rc" -eq 0 ] && [ "$old_rc" -ne 0 ]; then
  echo "OVERALL: ORDERING PROVEN (old fails / new passes, identical fixture, node-free initial PATH)"
else
  echo "OVERALL: PROOF FAILED"
fi
