# DF-H3-52 — arm 1 fresh-install version battery (h3-foreman-2026-11-22-09-37-10)

Executed 2026-11-22T09:40..09:43 UTC from a clean scratch venv (no sibling checkouts).
RESULT: FAIL — the defect is LIVE on the published 0.1.6 wheel. AC1 is not met; the row cannot close.

## Environment

- Fresh venv: `/home/kara/.hermes/cache/scratch/df-h3-52/venv-df52` (python3.14)
- Install: `pip install h3-harness-sdk==0.1.6` (rc 0)
- Registry: PyPI latest = 0.1.6; artifacts uploaded 2026-09-21T04:42:2xZ
  (both wheel and sdist) — months before fix 09b6596 landed on sdk-python main,
  so no released artifact can carry the fix. Registry metadata was never the issue;
  the wheel's payload is.

## Measured surfaces (version strings)

| Surface | Command | Output | Expected | Verdict |
|---|---|---|---|---|
| module | `python -c "import h3_harness; print(h3_harness.__version__)"` | `0.1.5` | 0.1.6 | FAIL |
| dist-info | `importlib.metadata.version('h3-harness-sdk')` | `0.1.6` | 0.1.6 | (reference) |
| wheel payload | `cat .../site-packages/h3_harness/_version.py` | `__version__ = "0.1.5"` | derived from installed metadata | FAIL |
| /v1/health | echo harness on :9417, `curl -s http://localhost:9417/v1/health` | `"version":"0.1.5"` | 0.1.6 | FAIL |
| h3-test Target line | second fresh venv `hermes-h3-shim`, `h3-test --endpoint http://localhost:9417 --categories health` | `Target health: version=0.1.5 uptime_seconds=38 active_sessions=0` | 0.1.6 | FAIL |

Exact /v1/health body:
`{"status":"ok","version":"0.1.5","active_sessions":0,"capabilities":["tool_call","llm_call","text","wait","delegate","end"],"degraded_reason":null,"error":null,"protocol_version":"1.0","transport":"rest","uptime_seconds":5}`

h3-test battery v0.2.0 against the target: Health & Protocol 7/7 PASSED, TOTAL 7/7 PASSED
(the compliance suite passes; the version identity claim is what fails, not protocol behavior).

Installed wheel _version.py (verbatim tail):
```
__version__ = "0.1.5"
```

## Conclusion on the row

- AC1 (fresh-install identity): FAIL — module version 0.1.5 ≠ installed dist-info 0.1.6;
  /v1/health and the h3-test Target health line both serve 0.1.5.
- The 2026-11-21 PM note's "ARM 1 PREMISE CHANGED" reading was based on
  `pypi.org/pypi/h3-harness-sdk/json => 0.1.6` (registry metadata) only. The registered name
  and the served wheel payload are different surfaces; the stale `__version__` is still shipped.
- Arms 2 and 3 remain met as previously verified (test_version_authority.py on sdk-python main;
  CONTRIBUTING.md version-bump checklist).
- What remains on this row: cut the next release (0.1.7) from a tree containing 09b6596 so the
  wheel's `_version.py` derives from installed metadata, then re-run this battery and re-verify.
  Release execution = owner-gated per the 2026-11-21 foreman receipt
  (.coding-hermes/evidence/h3-foreman-2026-11-21-09-02-15/receipt.md); unattended PyPI publish
  was not executed this tick.
- Full transcript incl. battery output: this file + the two fresh venvs remain at
  /home/kara/.hermes/cache/scratch/df-h3-52/ for 24h.
