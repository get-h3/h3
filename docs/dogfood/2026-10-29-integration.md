# H3 dogfood report — 2026-10-29

ch:trace tick=h3-dogfood-2026-10-29-12-06-47 project=h3 repo-head=120308cab481863f7480f7e44e713ccbd35b2191

## Promise
H3 claims that an integrator can clone the umbrella repository, install the published `hermes-h3-shim` CLI in a Python virtual environment, start a documented Go echo harness, and run `h3-test` to obtain a 48/48 H3-compliance result. The repository also documents `make verify` for repository consistency and `make verify-roundtrip` for cross-language protocol verification.

## Real-use result
Verdict: SHIPPABLE for the exercised documented path. The clean bunker agent cloned the public repository at HEAD 120308c, created a venv, installed `hermes-h3-shim` 0.2.0 from PyPI, cloned `get-h3/sdk-go`, started the Go echo harness on `PORT=9297`, confirmed `GET /v1/health` HTTP 200, and ran `h3-test --endpoint http://127.0.0.1:9297`: 48/48 passed, exit 0. The battery reported 15 Error & Edge Cases and 5 Stress & Performance tests.

Local repository checks also passed: `make verify` exit 0 with `make verify: ALL PASS — umbrella repo is self-consistent`; `make verify-roundtrip` exit 0 with `Passed: 6 Failed: 0` and `QV-PROTO-04: Cross-language protocol round-trip verification PASSED`.

## Install leg
The mandatory ephemeral leg executed on `bunker-mvp`, agent `df-h3-20261029-120647`. The public clone resolved to HEAD `120308cab481863f7480f7e44e713ccbd35b2191`. The documented install path completed with `INSTALL_SECONDS=39` (clone, venv, PyPI install, sdk-go clone, and harness startup). The smoke battery completed with `BATTERY_RC=0`, `TOTAL 48/48 PASSED`, and duration 0.49s. The agent was destroyed successfully; a subsequent `bunker info` returned `not_found` and the server census showed only the pre-existing `crier-lab` agent. No credentials, visibility changes, or permissions changes were used.

The installation evidence is independent of the local checkout and is not a silent skip.

## Performance
Headline operations were measured without changing the target:

- Clean-clone `make verify`: hyperfine, 2 warmups and 7 runs; mean 848.5 ms ± 227.4 ms, range 563.9–1106.5 ms.
- Local `make verify`: one cold-ish run at 1.52s wall (`real 1.52`, `user 0.57`, `sys 0.82`).
- Local `make verify-roundtrip`: 10.79s wall (`real 10.79`, `user 4.92`, `sys 1.86`), with all six phases passing.
- Fresh-agent compliance battery: 0.49s after installation, with p50 2.27ms and p95 59.03ms.
- Fresh-agent install path: 39s, dominated by network/package/tool setup rather than a repeated product operation.

Nothing measured was slow enough to justify a new PERF row. No profile was run because the repeatable user-facing operations were sub-second to low-seconds and the only multi-second operation was a one-time cross-language verification/install workflow with no demonstrated user-noticeable hot path.

## Findings and open coverage
No new product finding was filed. Existing board rows remain the owning records for open coverage questions, including QA-H3-28 (generic QA battery vacuity), QA-H3-PERF-1 (prior uncollected battery), QA-H3-FOREMAN-4 (generic missing-config detector coverage), and README-5 (the documented Go 1.21+ prerequisite is below sdk-go's go 1.22 floor). This run did not re-file or alter those rows. The local and bunker evidence above proves the documented H3 path, not closure of those separate QA, documentation, or release rows.

The prior tracked usage skill still contained stale coaching saying the Go example and scaffold ignored PORT even though DF-H3-9 was fixed. The verified correction is included in this run's tracked `skills/h3-usage/SKILL.md` artifact; no duplicate board row was created because DF-H3-9/README-4 already own that defect class.

The stand-in path `/home/kara/.hermes/stand-in/dogfood/h3` has no `tasks.jsonl`; canonical board resolution was `/home/kara/get-h3/h3/.coding-hermes/board/tasks.jsonl`. The canonical board was not modified.
