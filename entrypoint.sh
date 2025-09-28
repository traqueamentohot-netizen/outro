#!/usr/bin/env bash
set -euo pipefail

# Caminhos efetivos (conforme seus logs)
APP_DIR="/app"
BOT_DIR="/app/bot_gesto"

export BRIDGE_BOT_DIR="$BOT_DIR"

echo "[entry] APP_DIR=$APP_DIR"
echo "[entry] BRIDGE_BOT_DIR=$BRIDGE_BOT_DIR"
ls -la "$APP_DIR" || true
ls -la "$BOT_DIR" || true

# 1) Sobe o bot (se existir)
if [ -f "$BOT_DIR/bot.py" ]; then
  echo "[entry] starting bot.py ..."
  python -u "$BOT_DIR/bot.py" &
else
  echo "⚠️  $BOT_DIR/bot.py não encontrado; seguindo sem bot"
fi

# 2) Sobe o Bridge (app_bridge.py está em /app)
echo "[entry] starting bridge on :${PORT:-8080} ..."
exec gunicorn -k uvicorn.workers.UvicornWorker --chdir "$APP_DIR" -b 0.0.0.0:${PORT:-8080} app_bridge:app