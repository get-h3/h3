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
#                       Negative proof: make verify-board-header-selftest.
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
#                       It needs the sibling SDK repos next to this one on disk
#                       (../sdk-python, ../sdk-go, ../sdk-typescript) plus
#                       go/node/npx; when a sibling is missing the script's own
#                       "requires the sibling SDK repos, which are missing: ..."
#                       message reaches the user unchanged.
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

.PHONY: verify verify-docs verify-specs verify-count verify-json-fences verify-qa-target verify-qa-target-selftest verify-tick-chain verify-tick-chain-selftest verify-tree-census-selftest verify-board-header verify-board-header-selftest verify-commit-msg verify-roundtrip verify-all release

verify: verify-docs verify-specs verify-count verify-json-fences verify-qa-target verify-tick-chain verify-board-header verify-commit-msg
	@echo "make verify: ALL PASS — umbrella repo is self-consistent"
	@echo "make verify: SCOPE — docs + repo-consistency checks only (no code executed; both DuckBrain checks are read-only and report UNVERIFIED when their substrate is absent — jq/curl/token-file/board for the tick-chain guard, python3/token env/board for the independent tree-census walker); code-level verification is 'make verify-roundtrip' (CI: roundtrip.yml)."

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
	@echo "make verify: DuckBrain tick-chain drift/window census (H3-GAP-098)"
	@sh scripts/check-duckbrain-tick-chain.sh
	@echo "make verify: independent DuckBrain tree-census walker (H3-GAP-099)"
	@if command -v python3 >/dev/null 2>&1; then python3 scripts/duckbrain-tree-census.py h3 --start 418 --end auto $${H3_TREE_CENSUS_ARGS:-}; else echo "duckbrain-tree-census: UNVERIFIED — python3 not found on PATH (the independent census was not run)"; fi

verify-tick-chain-selftest:
	@echo "make verify-tick-chain-selftest: positive + negative proof for the tick-chain checker (H3-GAP-098)"
	@sh scripts/check-duckbrain-tick-chain-selftest.sh
	@echo "make verify-tick-chain-selftest: positive + negative proof for the independent tree-census walker (H3-GAP-099)"
	@sh scripts/check-duckbrain-tree-census-selftest.sh

verify-tree-census-selftest:
	@echo "make verify-tree-census-selftest: positive + negative proof for the tree-census walker (H3-GAP-099)"
	@sh scripts/check-duckbrain-tree-census-selftest.sh

verify-board-header:
	@echo "make verify: board-header self-consistency guard (H3-GAP-099)"
	@sh scripts/check-board-header-consistency.sh

verify-board-header-selftest:
	@echo "make verify-board-header-selftest: positive + negative proof for the board-header guard (H3-GAP-099)"
	@sh scripts/check-board-header-consistency-selftest.sh

verify-commit-msg:
	@echo "make verify: commit-message skip-directive guard (HEAD)"
	@sh scripts/check-ci-skip-tokens.sh

verify-roundtrip:
	@echo "make verify-roundtrip: cross-language round-trip code suite (needs the sibling SDK repos)"
	bash integration/roundtrip/roundtrip.sh

verify-all: verify verify-roundtrip

# The release driver. DRY-RUN BY DEFAULT — a bare `make release` runs the gate
# and prints the plan without mutating anything (see the header comment above).
# The cut is a separate, explicit opt-in:  bash scripts/release.sh --execute
release:
	@echo "make release: release driver (scripts/release.sh) — DRY-RUN by default; nothing is tagged, pushed or written"
	@bash scripts/release.sh
