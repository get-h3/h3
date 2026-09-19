# DF-H3-13: Config path verification

Status: verified; no product change required.

The shim CLI's default config path is user-owned and runtime-dependent:

```python
CONFIG_PATH = Path.home() / ".hermes" / "h3" / "config.yaml"
```

The CLI also honors a non-blank `HERMES_H3_CONFIG` override. Explicit `--config` has precedence over the environment override, which has precedence over the `Path.home()` default.

Reproducible evidence, run 2026-09-19:

```text
cd /home/kara/get-h3/shim
.venv/bin/python -m pytest tests/test_cli.py -k ConfigPath
14 passed
```

The focused tests include `TestConfigPathEnvOverride`: the override is honored, `~` expands against the active HOME, whitespace is stripped, and a blank override falls back to the default. An isolated-HOME probe resolved the default to `/tmp/df13-home/.hermes/h3/config.yaml`; setting `HERMES_H3_CONFIG=/tmp/df13-scratch.yaml` resolved to `/tmp/df13-scratch.yaml`.

The earlier `/tmp/dj-judge/run2/.hermes/h3/config.yaml` observation came from the judge process's sandboxed HOME. It is therefore expected that a process launched with that HOME resolves a path beneath `/tmp/dj-judge/run2`; it does not indicate a baked-in application path.

The real user config was not modified. No source change is required, and DF-H3-13 is closed as a judge-environment artifact.
