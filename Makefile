# H3 umbrella verification entry point (GAP-053).
#
# A fresh clone of get-h3/h3 alone must be able to verify itself:
#   make verify
# Runs with zero dependencies (POSIX shell + coreutils) — no venv, no network.
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
#
# SCOPE (QA-H3-7): every check above is a docs/repo-consistency guard — `make
# verify` never executes SDK code (the qa-target check inspects the checkout's
# identity, not its code). That is deliberate: it must keep working on a bare
# fresh clone with zero deps (POSIX shell + coreutils + git — which the
# commit-msg guard already required) and zero siblings.
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
# CI runs the round-trip only through .github/workflows/roundtrip.yml, which is
# path-filtered to integration/roundtrip/** — so a docs-only push gets green CI
# that never executed code. That filter is a deliberate design, not an accident;
# the naming above is what makes the difference visible. See CONTRIBUTING.md.

.PHONY: verify verify-docs verify-specs verify-count verify-json-fences verify-qa-target verify-qa-target-selftest verify-commit-msg verify-roundtrip verify-all

verify: verify-docs verify-specs verify-count verify-json-fences verify-qa-target verify-commit-msg
	@echo "make verify: ALL PASS — umbrella repo is self-consistent"
	@echo "make verify: SCOPE — docs + repo-consistency checks only (no code executed); code-level verification is 'make verify-roundtrip' (CI: roundtrip.yml)."

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

verify-commit-msg:
	@echo "make verify: commit-message skip-directive guard (HEAD)"
	@sh scripts/check-ci-skip-tokens.sh

verify-roundtrip:
	@echo "make verify-roundtrip: cross-language round-trip code suite (needs the sibling SDK repos)"
	bash integration/roundtrip/roundtrip.sh

verify-all: verify verify-roundtrip
