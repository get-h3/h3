# FIX 3 · node+npm toolchain bootstrap (QA-HERMES-CANOPY-32, 2026-09-24):
# the JIT agent image ships NO node/npm, so the ui-probe frontend/ arm
# (setsid npm run dev) dies "No such file or directory" on every repo that
# only serves a frontend/ Vite/npm surface. Install user-space Node LTS
# v22.15.0 (proven resolving 2026-09-24) into ~/tools/node, same best-effort
# pattern as FIX 1/FIX 2: offline agents log a WARN and continue.
if ! command -v node npm >/dev/null 2>&1; then
  mkdir -p ~/tools
  if curl -fsSL -o /tmp/node-v22.15.0-linux-x64.tar.xz https://nodejs.org/dist/v22.15.0/node-v22.15.0-linux-x64.tar.xz >\$LOGD/node.log 2>&1 && tar -xJf /tmp/node-v22.15.0-linux-x64.tar.xz -C ~/tools >\$LOGD/node.log 2>&1 && mv ~/tools/node-v22.15.0-linux-x64 ~/tools/node && head -c 4 ~/tools/node/bin/node | grep -q ELF; then
    export PATH="\$HOME/tools/node/bin:\$PATH"
    cell toolchain-bootstrap OK "node+npm installed (\$(node --version 2>/dev/null || echo version n/a))"
  else
    echo "WARN: node+npm install failed (offline agent?) — ui-probe frontend/ arm will grade ENV-BLOCKED: \$(tail -1 \$LOGD/node.log 2>/dev/null)" >&2
  fi
fi
