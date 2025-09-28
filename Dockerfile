# Cria o entrypoint.sh diretamente
RUN <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

echo "[entry] pwd=$(pwd)"
BRIDGE_DIR="${BRIDGE_DIR:-/app/Typebot-conecet/outro}"

if [ ! -f "$BRIDGE_DIR/app_bridge.py" ]; then
  echo "[entry] Default BRIDGE_DIR não tem app_bridge.py. Buscando automaticamente…"
  BRIDGE_DIR=$(python - <<'PY'
import os, sys
for root, dirs, files in os.walk('/app', topdown=True):
    if 'app_bridge.py' in files:
        print(root); sys.exit(0)
print('')
PY
)
  if [ -z "$BRIDGE_DIR" ]; then 
    echo "❌ app_bridge.py não encontrado"
    find /app -maxdepth 4 -name app_bridge.py -printf "→ %h/app_bridge.py\n" || true
    exit 1
  fi
fi

export BRIDGE_BOT_DIR="${BRIDGE_BOT_DIR:-$BRIDGE_DIR/bot_gesto}"
echo "[entry] BRIDGE_DIR=$BRIDGE_DIR"
echo "[entry] BRIDGE_BOT_DIR=$BRIDGE_BOT_DIR"

ls -la "$BRIDGE_DIR" || true
ls -la "$BRIDGE_BOT_DIR" || true

exec gunicorn -k uvicorn.workers.UvicornWorker \
  --chdir "$BRIDGE_DIR" -b 0.0.0.0:${PORT} app_bridge:app
BASH

RUN chmod +x /app/entrypoint.sh
