# H3 umbrella verification entry point (GAP-053).
#
# A fresh clone of get-h3/h3 alone must be able to verify itself:
#   make verify
# Runs with zero *required* dependencies (POSIX shell + coreutils + git) — no
# venv, no outbound network. One check (tick-chain, #7) additionally uses
# jq/curl against DuckBrain on localhost; when those are absent it reports
# UNVERIFIED instead of passing (see SCOPE below).
#
# Checks:
#   1. docs-link      — every relative .md link in README.md and specs/_index.md
#                       resolves to a file that exists in the repo.
#   2. spec-index     — every spec file under specs/ is listed in specs/_index.md,
#                       and every spec listed in the index resolves to a real file.
#   3. count          — the compliance-test count in scripts/test-count.txt is the
#                       single source of truth: the sibling battery's
#                       EXPECTED_TEST_COUNT must match it and no current-state doc
#                       may still quote a retired count (GAP-072).
#   4. json-fences    — every ```json fenced block in the tracked markdown
#                       (README.md, specs/*.md, docs/**/*.md) must parse as JSON, and
#                       a payload that is deliberately abbreviated (`...`) must say
#                       so on the failing line (H3-GAP-083). This pins the class a
#                       board row mis-reported as "not valid JSON": the payload was
#                       fine, a non-greedy extractor truncated it at a mid-line ```
#                       inside a string value. The guard also fails an unclosed fence.
#   5. qa-target      — the QA/verification target of this umbrella must be a
#                       real checkout of THIS repo (QA-H3-1). A path that does
#                       not exist, is not a work tree, or is a sibling repo
#                       fails here instead of degrading into an empty result
#                       that reads as clean: zero cells is UNVERIFIED, never a
#                       pass. The guard also takes a candidate directory as an
#                       argument, so a runner can pre-flight its own target.
#                       Negative proof: make verify-qa-target-selftest.
#   6. commit-msg     — the HEAD commit message carries no GitHub workflow-skip
#                       directive (H3-CI-001). GitHub matches one ANYWHERE in the
#                       message of the pushed head commit — prose included — so a
#                       board subject that merely mentions it ("NO [ci skip]: ...")
#                       silently skips every push-triggered workflow. Use a
#                       workflow's paths filter, never a message token.
#                       Kept LAST: it inspects HEAD, so it passes only after the
#                       commit that carries it has landed.
#   7. tick-chain     — the DuckBrain tick-key census for namespace `h3`
#                       (H3-GAP-098). Reads the WHOLE key tree and classifies
#                       every tick-ish path: the canonical bare /tick/<N> chain,
#                       the pre-#418 legacy series (/project/h3/tick/408..427),
#                       DRIFT (any other path ending in /tick/<N>, N >= 418),
#                       and legitimate timestamped slug keys (non-fatal). The
#                       bare chain must be complete from 418 to the board's
#                       ticks_total - 1, and no unknown-shaped tick key may
#                       exist: the two twins tick #459 deliberately backfilled
#                       (452/453) are allowlisted and warned, every OTHER drifted
#                       key fails. A census that reads only the bare keys reports
#                       a drifted chain as "contiguous" — this is the census that
#                       cannot (ticks #452/#453 wrote drifted keys and left holes
#                       in the bare chain at both numbers).
#                       Negative proof: make verify-tick-chain-selftest.
#                       The target then runs the INDEPENDENT census walker
#                       scripts/duckbrain-tree-census.py (H3-GAP-099, the
#                       promotion of the 79th/80th NEVER-DONE audits' ad-hoc
#                       /tmp walker, ticks #469/#474) in LIVE mode against the
#                       same namespace and requires exit 0: it prints the
#                       audit-publishable line
#                           present=<N> missing=[..] unknown_drift=[..]
#                       and fails on a hole or on an unknown-shaped tick key at
#                       N >= 418. Two readers of one tree is the point — a
#                       disagreement between them is the signal, so it is
#                       deliberately a second implementation rather than a
#                       second call into the guard. UNVERIFIED (exit 0) when
#                       the token env var H3OPS_DUCKBRAIN_API_KEY is unset, the
#                       fetch fails, or the board header cannot be read; the
#                       token is read from the environment only (never a silent
#                       token-file fallback), so a host that keeps its token in
#                       a file arms it explicitly:
#                           H3_TREE_CENSUS_ARGS="--url http://localhost:3000 \
#                               --token-file ~/.duckbrain/h3.token" make verify-tick-chain
#                       Negative proof: make verify-tree-census-selftest (its
#                       selftest is also run by make verify-tick-chain-selftest).
#   8. board-header  — the board's OWN header is self-consistent (H3-GAP-099).
#                       board.jsonl is a one-line object whose last_commit and
#                       ticks_total every reader believes without checking, and
#                       nothing verified either. Measured 2026-09-21: BOTH had
#                       gone stale — the post-push header sync was skipped by one
#                       tick's last commit and last_commit sat three commits
#                       behind (the same drift class already hand-repaired twice,
#                       #459 ticks_idle and #463 cooldown_s, where a Tier-2 judge
#                       had to catch the foreman reading the STALE HEADER instead
#                       of config). This check makes it catchable without a judge:
#                       last_commit must be HEAD or HEAD's parent (the two-phase
#                       sync runs at most one commit ago), ticks_total must not
#                       trail the highest tick the event log records, every tick
#                       in the recent window must have an event, and the working
#                       header must equal the committed one. Tick numbers are read
#                       from BOTH shapes (top-level tick_number and detail-embedded
#                       tick) — reading one shape only reports the other as a hole
#                       (an independent audit did exactly that and reported four
#                       phantom missing ticks on 2026-09-21).
#                       SCOPE: staleness and holes only — it cannot prove the named
#                       commit is the CORRECT pushed one, and it does not read the
#                       event log for anything but tick coverage.
#                       On a copy whose history cannot adjudicate the named commit
#                       it reports UNVERIFIED and exits 0 instead of FAILing:
#                       shallow/grafted, fewer than two commits, or UNANCHORED (no
#                       ref under refs/remotes/* — the archive+git-init sync shape
#                       the fresh-install battery uses, however many local commits
#                       that copy has since gained; QA-H3-20). A resolvable stale
#                       header still FAILs with the PUBLIC-HEAD-VERIFY-FAIL line.
#                       Negative proof: make verify-board-header-selftest.
#   9. tags-table    — the '## Tags' table in docs/releases.md names EXACTLY the
#                       tag set git reports, two-directionally: every tag from
#                       `git ls-remote --tags origin` (peeled ^{} lines dropped)
#                       must appear in the table, and every table row must name
#                       a tag git actually has. docs/releases.md is on the
#                       pages.yml publish path, so a stale table is PUBLIC —
#                       this is the guard for the drift DF-H3-44 closed
#                       (v0.2.0/v0.3.0 cut+pushed while the table listed only
#                       v0.1.0). When origin is unreachable it degrades honestly
#                       to `git tag -l` and the verdict reads "PASS (local
#                       degrade)". Negative proof:
#                       sh scripts/check-tags-table.sh --selftest
#
# THE BOARD-WRITING CLOSE-OUT (DF-H3-25) — `make board-close`
#
# The header is a WRITE problem, and a guard catching it is not a fix. The
# write-back regressed five times (#459, #463/#464, #480, #481) while check 8
# caught every occurrence: the last two ticks skipped it, so a fresh public
# clone of this repo failed `make verify` (last_commit four commits behind,
# ticks_total 479 against an event log already recording #481).
# scripts/sync-board-header.sh is the WRITER, and this target is the single
# unconditional step a board-writing tick ends with:
#
#   make board-close          # rewrites line 1 of .coding-hermes/board/board.jsonl:
#                             #   last_commit = git rev-parse --short HEAD
#                             #   ticks_total = highest tick in events.jsonl
#                             #   last_tick   = now, UTC (YYYY-MM-DD HH:MM:SS)
#                             # idempotent (a re-run with nothing to re-pin writes
#                             # nothing), byte-preserving every other line, and it
#                             # refuses (non-zero, nothing written) rather than
#                             # guess — see the script's header for the refusals.
#
# The close-out contract, in order:
#
#   1. append the tick's events (and any board rows) to the board files
#   2. make board-close                       <- reasserts the hook, then the
#                                                header names the current HEAD
#   3. git commit the board files             <- the commit that carries the header
#
# Step 2 is TWO writes on purpose (QA-H3-27). scripts/ensure-board-close-hook.sh
# re-asserts the pre-commit block in the hooks directory git resolves — because
# installing it once is a one-shot: the block lives inside a pre-commit file this
# project does not own, and a reinstall of a SHARED hooks file (the gitreins hook
# on this host rewrites /var/tmp/foreign-hooks/pre-commit from its own template)
# silently removes it. Measured: 9th recurrence, a fresh public clone at 22bc708
# failed `make verify` with last_commit six commits behind because the two board
# commits before it ran with no block at all. So the close-out itself must not
# assume the block is still installed: it verifies it, reasserts it through the
# tracked installer when it is gone, and FAILS LOUDLY (non-zero, remedy printed)
# when it cannot — the board close-out stops before a stale header can land,
# instead of leaving the discovery to the next fresh-clone verify.
# scripts/sync-board-header.sh then writes the header. Proof:
# make verify-board-close-hook-selftest (its arm 11 reinstalls a gitreins-style
# hook over the resolved dir, proves the header goes stale without the block,
# then proves the close-out path puts it back and the next board commit re-pins).
#
# Step 3 is what makes check 8 pass at rest: the header then names the commit
# the board was written against — the board commit's parent — which is the
# strongest state that can exist, because a commit cannot contain its own hash
# (that is exactly why the guard's rule is "last_commit is HEAD or HEAD's
# parent"). Syncing AFTER the commit instead leaves an uncommitted header edit,
# which check D FAILs on; if a tick must commit again after the board commit,
# re-run `make board-close` and include the header in that commit.
#
# The step is deliberately NOT part of `make verify`: verify is read-only, runs
# on a fresh clone, and must never write a board. And it is deliberately not a
# post-push hook: a hook is what was skipped. Skipping the close-out is now
# loud in two places — check 8 fails, and it prints the greppable fleet line
# `PUBLIC-HEAD-VERIFY-FAIL:` (alert recipe in scripts/
# check-board-header-consistency.sh). Negative proof, including the syncer:
# make verify-board-sync-selftest.
#
# A hook is only structural where git LOOKS. `core.hooksPath` overrides
# `.git/hooks` entirely, and a linked worktree has no hooks dir of its own, so
# the installer (scripts/install-board-close-hook.sh) resolves the hooks
# directory with `git rev-parse --git-path hooks` and installs THERE. Before
# QA-H3-22-R2 it hardcoded `.git/hooks/pre-commit`: on a host with a global
# hooks path the block installed, printed OK, and never ran — which is why this
# class came back eight times. The managed block is silent in repos that do not
# carry scripts/pre-commit-board-close.sh, so installing it into a SHARED hooks
# dir cannot affect unrelated repos. Proof: make verify-board-close-hook-selftest
# (its RED arm fails a board commit that leaves the header stale while
# core.hooksPath is set; its GREEN arm shows the same commit re-pinning the
# header to the commit's parent).
#
# The board's OTHER closeout write is the namespace tick record,
# scripts/duckbrain-tick-record.sh <N> (DF-H3-23) — the canonical writer for the
# `/tick/<N>` memory key. A board-writing tick's close-out is therefore two
# writes, both before the board commit: the header (make board-close) and the
# tick record. They are separate on purpose: the record writer degrades to
# UNVERIFIED when DuckBrain/jq/curl/the token are absent, and a degraded memory
# write must never be the thing that decides whether the repo's own header gets
# written.
#
# SCOPE (QA-H3-7): checks 1-6 above are docs/repo-consistency guards — `make
# verify` never executes SDK code (the qa-target check inspects the checkout's
# identity, not its code). That is deliberate: it must keep working on a bare
# fresh clone with zero deps (POSIX shell + coreutils + git — which the
# commit-msg guard already required) and zero siblings.
# The 7th check (tick-chain) is the one exception and is built to preserve that
# property honestly: it probes DuckBrain on localhost:3000 read-only, and when
# the service, jq, curl, the token file or the board header is missing it prints
# an explicit UNVERIFIED and exits 0 — absent tooling is UNVERIFIED, never PASS,
# so a fresh clone with no DuckBrain still gets a green gate that does not lie
# about what it read. The independent tree-census walker it also runs
# (scripts/duckbrain-tree-census.py, python3 stdlib — no jq) follows the same
# rule: python3 absent, the token env var unset, the fetch failing or the board
# header unreadable all print UNVERIFIED and exit 0, and only a tree that was
# actually READ can fail the target.
# The repo's only executable verification is the cross-language round-trip
# suite in integration/roundtrip/, exposed here as:
#
#   make verify-roundtrip — runs bash integration/roundtrip/roundtrip.sh from the
#                       repo root and PROPAGATES its exit code (no `|| true`).
#                       SELF-CONTAINED (H3-REVIEW-20261021-01): the suite stages
#                       a declared temporary workspace, resolving the sibling
#                       SDK repos (sdk-python, sdk-go, sdk-typescript) from local
#                       checkouts when they exist next to this repo and otherwise
#                       fetching them at the revisions pinned in
#                       integration/roundtrip/siblings.lock. A tree with ONLY h3/
#                       checked out therefore runs the code-level gate (needs
#                       git+network for the fetch, plus go/node/npx); pass
#                       ROUNDTRIP_WORKSPACE=<dir> to declare the workspace
#                       yourself, and see the script header for the
#                       H3_ROUNDTRIP_* / H3_SDK_*_REF knobs.
#   make verify-roundtrip-selftest — positive + negative proof for that
#                       workspace resolution (offline, resolve-only): pins are
#                       real SHAs, an h3-only tree fetches them from a file://
#                       mirror, local siblings are reused, and an unreachable
#                       mirror fails loudly naming sdk-python.
#   make verify-all   — verify verify-roundtrip (composite: docs guards + code).
#
#   make release      — the RELEASE DRIVER (scripts/release.sh), RELEASE-H3-003.
#                       DRY-RUN BY DEFAULT: it runs `make verify`, derives the
#                       next version from the conventional commits since the
#                       last tag (feat -> MINOR, breaking -> MAJOR, else PATCH),
#                       proves the tag is unused locally and at origin, and
#                       prints the exact steps a cut would take — mutating
#                       nothing (no tag, no push, no CHANGELOG write, no gh
#                       call). The cut itself needs the explicit opt-in:
#                           bash scripts/release.sh --execute
#                       which promotes the changelog, tags the verified commit
#                       (`git tag -a`), pushes ONLY the tag, and creates +
#                       verifies the GitHub Release object (`gh release
#                       create` / `gh release view` — a tag alone is not a
#                       Release, RELEASE-H3-002). It is deliberately NOT part
#                       of `make verify`: promoting the changelog writes into
#                       the repo, so it must never run in the gate.
#
# CI runs the round-trip only through .github/workflows/roundtrip.yml, which is
# path-filtered to integration/roundtrip/** — so a docs-only push gets green CI
# that never executed code. That filter is a deliberate design, not an accident;
# the naming above is what makes the difference visible. See CONTRIBUTING.md.

.PHONY: verify verify-prereqs verify-prereqs-early verify-docs verify-specs verify-count verify-tags verify-json-fences verify-qa-target verify-qa-target-selftest verify-tick-chain verify-tick-chain-selftest verify-tree-census-selftest verify-verdict-census verify-verdict-census-selftest verify-board-header verify-board-header-selftest verify-board-close-hook-selftest verify-board-sync-selftest board-close verify-commit-msg verify-roundtrip verify-roundtrip-selftest verify-all release

# PERF-1: make verify — bounded parallel prerequisites.
#
# The 10 guard prerequisites are independent read-only checks; run serially the
# composite is process-orchestration bound (hyperfine at bd4c5fa, 20 runs warm:
# MAKEFLAGS=-j1 2.901s ± 1.128s vs -j8 1.484s ± 0.362s — ~1.95x, and strace
# showed 83% of traced time in wait4, not in any single guard). The
# parallelism is therefore the DEFAULT of the target itself, not a caller-side
# flag, with a knob:
#
#   VERIFY_JOBS ?= 8                      # bounded fan-out for verify-prereqs
#   make VERIFY_JOBS=16 verify            # wider/narrower without editing
#
# `verify` carries NO direct guard prerequisites — the guards live ONLY in the
# fan-out graph below (verify-prereqs / verify-prereqs-early / the census
# edge). Their recipes (and each guard's verdict lines) are unchanged and
# byte-identical. Giving `verify` both the guard list AND the recursive recipe
# would run every guard twice — once serially as prerequisites of the outer
# make, once in the bounded-parallel sub-make (measured here first: the first
# cut of this change produced 2x the guard output and a slower run than the
# baseline). The recipe re-invokes make on the real prerequisite list,
# bounded:
#
#   $(MAKE) --no-print-directory -j$(VERIFY_JOBS) --output-sync=recurse \
#       verify-prereqs
#
# --output-sync=recurse (-Orecurse) is REQUIRED: it holds each guard's output
# whole, so no verdict line ever interleaves with a sibling's and every PASS /
# FAIL / UNVERIFIED stays attributable to the guard that printed it.
#
# CALLER-PINNED PARALLELISM WINS. When the caller (hyperfine leg, CI, a human)
# pinned -j via MAKEFLAGS (-j1, -jN or bare -j), the recipe delegates the
# flags unmodified — a literal -j$(VERIFY_JOBS) on the sub-make argv would
# OVERRIDE the caller's MAKEFLAGS value (measured on GNU Make 4.4.1: env
# MAKEFLAGS=-j1 + argv -j8 runs the sub-make at 8, so a -j1 timing leg would
# silently measure parallel and the speedup number would be fake). Detected on
# $(MAKEFLAGS), which carries exactly what the caller set (the sub-make's copy
# is never consulted): a -j token present -> pass-through; absent -> apply
# -j$(VERIFY_JOBS) -Orecurse. Output-sync is NOT caller-dependent: a caller
# -j never had it, and recursion adds no interleaving of its own.
#
# ORDERING CONTRACT (DF-H3-41/DF-H3-46, unchanged by the fan-out). The verdict
# census (verify-verdict-census) re-derives — read-only — whether the two
# DuckBrain guards degraded to UNVERIFIED on THIS run, so ALL PASS is only
# honest when it runs after them and after every other guard. In the serial
# target that was left-prerequisite order; here it is explicit graph order,
# encoded so it cannot depend on make's scheduling luck:
#   verify-prereqs-early — the 8 plain guards;
#   verify-verdict-census : verify-prereqs-early — runs after the early group;
#   verify-prereqs        : early group + census — always last.
# The census and tick-chain targets keep their own recipes untouched; the
# census was never named standalone by any script or workflow (grep at PERF-1),
# so the added edge changes no other invocation.
# PERF-2: the DEFAULT IS RE-MEASURED AND STAYS 8. hyperfine 1.20.0, GNU Make
# 4.4.1, 16 cores, -w 3 -r 6 per leg, /tmp/perf-2-sweep.json:
#
#   MAKEFLAGS=-j1 (serial control)   2.210 s ± 0.372
#   VERIFY_JOBS=2                    1.481 s ± 0.158
#   VERIFY_JOBS=4                    1.276 s ± 0.281
#   VERIFY_JOBS=6                    1.271 s ± 0.173
#   VERIFY_JOBS=8 (this default)     1.203 s ± 0.041   <- best mean AND tightest spread
#   VERIFY_JOBS=12                   1.233 s ± 0.107
#   VERIFY_JOBS=16                   1.249 s ± 0.163
#
# 8 is not a lucky number: it is where the critical path stops moving. Nine
# early guards fan out, but the composite's wall time is the SLOWEST REQUIRED
# GUARD plus the census tail — not the fan-out width. Per-guard on the same
# host (/tmp/perf-2-parts-fast.json, -w 1 -r 8; /tmp/perf-2-parts.json, -w 2 -r 5):
#
#   verify-tags (git ls-remote --tags origin)      1.314 s ± 0.118   <- the floor
#   verify-tick-chain (DuckBrain chain + walker)   0.545 s ± 0.074
#   verify-board-header                            0.141 s ± 0.053
#   verify-specs / -count / -json-fences           0.12-0.15 s each
#   verify-docs / -qa-target / -commit-msg         0.016-0.034 s each
#   verify-verdict-census (script, the tail)       0.029 s ± 0.009
#   full `make verify` at -j8                      1.267 s ± 0.079
#   raw `git ls-remote --tags origin`, no guard    1.063 s ± 0.096
#
# The parallel composite IS the tags guard (1.267 s wall against a 1.314 s
# prerequisite, inside their spreads): no VERIFY_JOBS value can compose below
# that, which is why the sweep is flat from 4 upward while the serial control
# stays at sum-of-guards. Raising the width past 8 only adds scheduler and
# -Orecurse buffering; lowering it to 4 buys nothing and costs spread (4 and 8
# are 1.276 vs 1.203 — the earlier sweep that "found" 4 best was overlapping
# noise, which is the trap this block exists to stop re-deriving).
#
# Acceptance (the row's own command, two independent -w 3 -r 6 runs on this
# host, /tmp/perf-2-baseline.json vs /tmp/perf-2-serial.json, the files hold
# run 2): the margin holds with room in both, and moves only with host load,
# never with the setting —
#   run 1  default 1.2698 s  serial 2.3799 s  = 1.87x
#   run 2  default 1.4875 s  serial 3.2255 s  = 2.17x  (higher host load:
#          user+sys per run rose ~0.4 s, both legs together)
# against the 1.15x floor. The remaining headroom is inside the tags guard's
# network round-trip (1.06 s of remote reach, ~0.25 s of git + shell), not in
# the orchestration: caching or deduping `git ls-remote` would change what that
# guard verifies — a guard-semantics decision, not a scheduling one. Measured
# and left alone, deliberately.
#
# ch:trace row=PERF-2 spec=Makefile:235-291 wave=none:serial-tick test=hyperfine-benchmark doc=none:perf-evidence prompt=none:perf-work evidence=/tmp/perf-2-baseline.json,/tmp/perf-2-serial.json,/tmp/perf-2-sweep.json,/tmp/perf-2-parts.json witness=commit verdict=none:pending commit=none:pending memory=none:perf-tuning
VERIFY_JOBS ?= 8

verify:
	@$(MAKE) --no-print-directory $(if $(findstring -j,$(MAKEFLAGS)),,-j$(VERIFY_JOBS) --output-sync=recurse) verify-prereqs
	@echo "make verify: ALL PASS — umbrella repo is self-consistent"
	@echo "make verify: SCOPE — docs + repo-consistency checks only (no code executed; both DuckBrain checks are read-only and report UNVERIFIED when their substrate is absent — jq/curl/token-file/board for the tick-chain guard, python3/token env/board for the independent tree-census walker); code-level verification is 'make verify-roundtrip' (CI: roundtrip.yml). VERDICT CENSUS (DF-H3-41/DF-H3-46): the DuckBrain guards are honest ALONE (absent substrate = UNVERIFIED lines, exit 0), but the composite used to end with ALL PASS regardless, so scripts/release.sh step 2 (exit code + this literal ALL PASS line) passed releases over a substrate nobody checked — measured on a real fresh machine as 6 UNVERIFIED lines + ALL PASS rc=0. The LAST prerequisite, verify-verdict-census (scripts/check-verdict-census.sh), re-derives both guards' UNVERIFIED conditions read-only and is what makes ALL PASS honest: it prints the census line 'N verified / M unverified (guard: <names>)', and ALL PASS only ever follows a clean census — M > 0 fails 'make verify' with an explicit FAIL line naming the guards whenever a DuckBrain token dir exists, and (DF-H3-48) degrades to the same disclosed token-less SKIP the composite takes when none does (single quotes here, not backticks: a backtick inside this double-quoted recipe would command-substitute and recursively re-invoke make verify — QA'd in tick-524), and only H3_ALLOW_UNVERIFIED=1 accepts the degraded run explicitly ('PASS (local degrade: M UNVERIFIED accepted via H3_ALLOW_UNVERIFIED)'), the same absent-substrate vocabulary the guards themselves use. The census mirrors the guards' degrade predicates (token/jq/curl/python3/board/args) and does not re-fetch the tree, so a reachable-but-truncated or unparseable DuckBrain answer remains the guards' own runtime UNVERIFIED output. Negative proof: make verify-verdict-census-selftest."

# The fan-out target. Prerequisite ORDER (left-to-right) is the honest-census
# contract made explicit: the 8 plain guards first, then the census, which
# itself waits on the early group (see the ordering block above). All targets
# are .PHONY (declared on the .PHONY line above), so the sub-make rebuilds
# every guard on every run.
verify-prereqs: verify-prereqs-early verify-verdict-census

verify-prereqs-early: verify-docs verify-specs verify-count verify-tags verify-json-fences verify-qa-target verify-tick-chain verify-board-header verify-commit-msg

verify-docs:
	@echo "make verify: docs-link check"
	@rc=0; \
	for f in README.md specs/_index.md; do \
		dir=$$(dirname $$f); \
		for link in $$(grep -oE '\]\([^)]*\.md[^)]*\)' $$f | sed -E 's/^\]\((.*)\)$$/\1/'); do \
			link=$${link%%#*}; \
			case "$$link" in http*|https*) continue ;; esac; \
			if [ ! -f "$$dir/$$link" ]; then echo "MISSING: $$f -> $$link"; rc=1; fi; \
		done; \
	done; \
	[ $$rc -eq 0 ] && echo "make verify: docs-link check PASS"; \
	exit $$rc

verify-specs:
	@echo "make verify: spec-index-vs-files check"
	@rc=0; \
	for f in specs/*.md; do \
		base=$$(basename $$f); \
		[ "$$base" = "_index.md" ] && continue; \
		grep -q "$$base" specs/_index.md || { echo "NOT IN INDEX: $$base"; rc=1; }; \
	done; \
	for base in $$(grep -oE '\([0-9]{2}-[^)]*\.md\)' specs/_index.md | tr -d '()'); do \
		[ -f "specs/$$base" ] || { echo "INDEX MISSING FILE: specs/$$base"; rc=1; }; \
	done; \
	[ $$rc -eq 0 ] && echo "make verify: spec-index-vs-files check PASS"; \
	exit $$rc

verify-count:
	@echo "make verify: compliance-test count guard"
	@sh scripts/check-test-count.sh

verify-tags:
	@echo "make verify: release tags-table guard (docs/releases.md vs git, DF-H3-44)"
	@sh scripts/check-tags-table.sh

verify-json-fences:
	@echo "make verify: json-fence payload guard"
	@sh scripts/check-json-fences.sh

verify-qa-target:
	@echo "make verify: QA target contract guard (QA-H3-1)"
	@sh scripts/check-qa-target.sh

verify-qa-target-selftest:
	@echo "make verify-qa-target-selftest: negative proof for the QA target guard (QA-H3-1)"
	@sh scripts/check-qa-target-selftest.sh

verify-tick-chain:
	@echo "make verify: DuckBrain census composition — tick-chain guard + independent walker, verdict-classified (DF-H3-46)"
	@sh scripts/verify-duckbrain-census.sh

verify-tick-chain-selftest:
	@echo "make verify-tick-chain-selftest: positive + negative proof for the tick-chain checker (H3-GAP-098)"
	@sh scripts/check-duckbrain-tick-chain-selftest.sh
	@echo "make verify-tick-chain-selftest: positive + negative proof for the independent tree-census walker (H3-GAP-099)"
	@sh scripts/check-duckbrain-tree-census-selftest.sh

verify-tree-census-selftest:
	@echo "make verify-tree-census-selftest: positive + negative proof for the tree-census walker (H3-GAP-099)"
	@sh scripts/check-duckbrain-tree-census-selftest.sh

# The composite verdict census (DF-H3-41 / DF-H3-46). The LAST prerequisite of
# `verify`: it re-derives the DuckBrain guards' UNVERIFIED conditions for this
# run and fails the composite when any guard would have printed UNVERIFIED, so
# the ALL PASS line above is only ever printed over a substrate whose guards
# would all have said VERIFIED. H3_ALLOW_UNVERIFIED=1 is the explicit local
# escape hatch (see the SCOPE line and the guard's header). DF-H3-48: on a
# machine with no DuckBrain token dir at all it takes the SAME disclosed
# token-less skip the composite gate takes, instead of failing the fresh clone
# the composite had just skipped (both stages must agree on that machine).
verify-verdict-census: verify-prereqs-early
	@echo "make verify: DuckBrain verdict census — the composite must not say ALL PASS over UNVERIFIED (DF-H3-41/DF-H3-46)"
	@sh scripts/check-verdict-census.sh

verify-verdict-census-selftest:
	@echo "make verify-verdict-census-selftest: positive + negative proof for the verdict census (DF-H3-41/DF-H3-46)"
	@sh scripts/check-verdict-census.sh --selftest

verify-board-header:
	@echo "make verify: board-header self-consistency guard (H3-GAP-099)"
	@sh scripts/check-board-header-consistency.sh

verify-board-header-selftest:
	@echo "make verify-board-header-selftest: positive + negative proof for the board-header guard (H3-GAP-099)"
	@sh scripts/check-board-header-consistency-selftest.sh
	@echo "make verify-board-header-selftest: positive + negative proof for the header WRITER, and the guard on its output (DF-H3-25)"
	@sh scripts/sync-board-header-selftest.sh
	@echo "make verify-board-header-selftest: positive + negative proof that the WRITER-SIDE HOOK installs where git actually looks (core.hooksPath / worktrees) and re-pins a real board commit (QA-H3-22-R2)"
	@bash scripts/install-board-close-hook-selftest.sh

# The installer's own battery, on its own (QA-H3-22-R2). It is part of
# verify-board-header-selftest; this target is for running it in isolation.
# It isolates GIT_CONFIG_GLOBAL, so it gives the same verdict on a host whose
# global core.hooksPath points at a shared hooks dir and on one with no hooks
# path at all — and its RED arm fails when a board commit leaves the header
# stale, which is the recurrence this row closes.
verify-board-close-hook-selftest:
	@echo "make verify-board-close-hook-selftest: the board-close hook installer resolves core.hooksPath and fires (QA-H3-22-R2)"
	@bash scripts/install-board-close-hook-selftest.sh

# The board-writing close-out (DF-H3-25). Not part of `make verify` — verify is
# read-only and runs on a fresh clone; this WRITES line 1 of the board header.
# Run it after the board edits and BEFORE the board commit (see the close-out
# contract in the header comment at the top of this Makefile).
#
# QA-H3-27: it first re-asserts the board-close pre-commit block in the hooks dir
# git resolves (ensure-board-close-hook.sh). That step is why a reinstall of a
# shared hooks file can no longer cost a board commit its header write-back; if
# the block cannot be reasserted the target FAILS, loudly, before the header is
# written. H3_SKIP_HOOK_ENSURE=1 (handled inside the ensure script, which prints
# a warning naming the now-unguarded close-out) is for a host whose shared hooks
# dir must not be touched.
board-close:
	@echo "make board-close: board-header write-back (DF-H3-25) + board-close hook reassert (QA-H3-27) — run this as the last step before the board commit" && bash scripts/ensure-board-close-hook.sh
	@sh scripts/sync-board-header.sh

verify-board-sync-selftest:
	@echo "make verify-board-sync-selftest: positive + negative proof for the board-header writer (DF-H3-25)"
	@sh scripts/sync-board-header-selftest.sh

verify-commit-msg:
	@echo "make verify: commit-message skip-directive guard (HEAD)"
	@sh scripts/check-ci-skip-tokens.sh

# ROUNDTRIP_WORKSPACE: declare the round-trip workspace instead of letting the
# script pick a temp dir. A declared workspace is KEPT after the run (so its
# MANIFEST.txt and generated fixtures can be inspected); a temp one is removed.
ROUNDTRIP_WORKSPACE ?=

verify-roundtrip:
	@echo "make verify-roundtrip: cross-language round-trip code suite (stages a workspace; sibling SDKs reused locally or fetched at integration/roundtrip/siblings.lock pins)"
	bash integration/roundtrip/roundtrip.sh $(if $(ROUNDTRIP_WORKSPACE),--workspace "$(ROUNDTRIP_WORKSPACE)")

verify-roundtrip-selftest:
	@echo "make verify-roundtrip-selftest: positive + negative proof for the round-trip workspace resolution (H3-REVIEW-20261021-01)"
	@sh scripts/check-roundtrip-selftest.sh

verify-all: verify verify-roundtrip

# The release driver. DRY-RUN BY DEFAULT — a bare `make release` runs the gate
# and prints the plan without mutating anything (see the header comment above).
# The cut is a separate, explicit opt-in:  bash scripts/release.sh --execute
release:
	@echo "make release: release driver (scripts/release.sh) — DRY-RUN by default; nothing is tagged, pushed or written"
	@bash scripts/release.sh
