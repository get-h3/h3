#!/bin/sh
# DF-H3-49 install leg, run 2: fresh clone + documented install (make install).
# No single quotes (upload transport mangles them); no fragile trailing lines.
set -eu
echo "== tools =="
git --version
python3 --version
python3 -m venv /tmp/venv-probe && rm -rf /tmp/venv-probe && echo VENV_OK
echo "== fresh clone =="
cd "$HOME"
rm -rf sdk-python
git clone --depth 1 https://github.com/get-h3/sdk-python.git
cd sdk-python
git log --oneline -1
echo "== make install =="
make install
echo "INSTALL_RC=0"
echo "LEG2_COMPLETE"
