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
#   5. commit-msg     — the HEAD commit message carries no GitHub workflow-skip
#                       directive (H3-CI-001). GitHub matches one ANYWHERE in the
#                       message of the pushed head commit — prose included — so a
#                       board subject that merely mentions it ("NO [ci skip]: ...")
#                       silently skips every push-triggered workflow. Use a
#                       workflow's paths filter, never a message token.
#                       Kept LAST: it inspects HEAD, so it passes only after the
#                       commit that carries it has landed.

.PHONY: verify verify-docs verify-specs verify-count verify-json-fences verify-commit-msg

verify: verify-docs verify-specs verify-count verify-json-fences verify-commit-msg
	@echo "make verify: ALL PASS — umbrella repo is self-consistent"

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

verify-commit-msg:
	@echo "make verify: commit-message skip-directive guard (HEAD)"
	@sh scripts/check-ci-skip-tokens.sh
