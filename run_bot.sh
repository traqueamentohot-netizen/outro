#!/usr/bin/env bash
set -euo pipefail

BOT_DIR="/app/bot_gesto"

echo "[run_bot] pwd=$(pwd)"
echo "[run_bot] BOT_DIR=$BOT_DIR"
if [ ! -f "$BOT_DIR/bot.py" ]; then
  echo "❌ /app/bot_gesto/bot.py não encontrado"; ls -la "$BOT_DIR" || true; exit 1
fi

# Vars críticas (mascaradas)
mask(){ v="$1"; [ -z "${v:-}" ] && echo "<unset>" || echo "${v:0:3}***${v: -3}"; }
echo "[run_bot] BOT_USERNAME=$(echo ${BOT_USERNAME:-<unset>})"
echo "[run_bot] TELEGRAM_BOT_TOKEN=$(mask "${TELEGRAM_BOT_TOKEN:-}")"
echo "[run_bot] DATABASE_URL=$( [ -z "${DATABASE_URL:-}" ] && echo "<unset>" || echo "<set>")"
echo "[run_bot] REDIS_URL=$( [ -z "${REDIS_URL:-}" ] && echo "<unset>" || echo "<set>")"

# Checagens rápidas em Python (aiogram e imports)
python - <<'PY'
import importlib, os, sys
print("[py] python", sys.version)
for mod in ["aiogram","sqlalchemy","redis"]:
    try:
        importlib.import_module(mod)
        print(f"[py] ok import {mod}")
    except Exception as e:
        print(f"[py] FAIL import {mod} -> {e}")
        raise SystemExit(1)
p = "/app/bot_gesto/bot.py"
print("[py] bot.py exists:", os.path.isfile(p))
PY

echo "[run_bot] iniciando bot.py..."
exec python -u "$BOT_DIR/bot.py"