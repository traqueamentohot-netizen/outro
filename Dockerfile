# =============================
# Dockerfile — Bridge (auto deps + auto path)
# =============================
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="/app" PORT=8080

WORKDIR /app

# Sistema básico
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc g++ make libpq-dev curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Copia tudo para o contexto /app
COPY . /app

# Instala dependências:
# 1) /app/requirements.txt (raiz do build)
# 2) /app/Typebot-conecet/requirements.txt
# 3) /app/Typebot-conecet/outro/requirements.txt
# Fallback: instala um conjunto mínimo se nenhum requirements existir
RUN bash -lc '\
set -e; \
if [ -f /app/requirements.txt ]; then \
  echo "[deps] Using /app/requirements.txt"; pip install --no-cache-dir -r /app/requirements.txt; \
elif [ -f /app/Typebot-conecet/requirements.txt ]; then \
  echo "[deps] Using /app/Typebot-conecet/requirements.txt"; pip install --no-cache-dir -r /app/Typebot-conecet/requirements.txt; \
elif [ -f /app/Typebot-conecet/outro/requirements.txt ]; then \
  echo "[deps] Using /app/Typebot-conecet/outro/requirements.txt"; pip install --no-cache-dir -r /app/Typebot-conecet/outro/requirements.txt; \
else \
  echo "[deps] No requirements.txt found. Installing minimal set..."; \
  pip install --no-cache-dir fastapi pydantic gunicorn uvicorn redis cryptography user-agents geoip2 requests SQLAlchemy psycopg2-binary prometheus_client python-dotenv aiogram; \
fi \
'

# Entrypoint: encontra o app_bridge.py e inicia o Gunicorn no diretório correto
RUN bash -lc 'cat > /app/entrypoint.sh << "BASH"\n\
#!/usr/bin/env bash\n\
set -euo pipefail\n\
echo \"[entry] pwd=$(pwd)\"\n\
# Caminho padrão (seu caso): Typebot-conecet/outro\n\
BRIDGE_DIR=\"${BRIDGE_DIR:-/app/Typebot-conecet/outro}\"\n\
if [ ! -f \"$BRIDGE_DIR/app_bridge.py\" ]; then\n\
  echo \"[entry] Default BRIDGE_DIR não tem app_bridge.py. Buscando automaticamente…\"; \
  BRIDGE_DIR=$(python - <<\"PY\"\n\
import os, sys\n\
for root, dirs, files in os.walk('/app', topdown=True):\n\
    if 'app_bridge.py' in files:\n\
        print(root); sys.exit(0)\n\
print('')\n\
PY\n\
)\n\
  if [ -z \"$BRIDGE_DIR\" ]; then echo \"❌ app_bridge.py não encontrado\"; find /app -maxdepth 4 -name app_bridge.py -printf \"→ %h/app_bridge.py\\n\" || true; exit 1; fi\n\
fi\n\
export BRIDGE_BOT_DIR=\"${BRIDGE_BOT_DIR:-$BRIDGE_DIR/bot_gesto}\"\n\
echo \"[entry] BRIDGE_DIR=$BRIDGE_DIR\"; echo \"[entry] BRIDGE_BOT_DIR=$BRIDGE_BOT_DIR\"\n\
ls -la \"$BRIDGE_DIR\" || true; ls -la \"$BRIDGE_BOT_DIR\" || true\n\
exec gunicorn -k uvicorn.workers.UvicornWorker --chdir \"$BRIDGE_DIR\" -b 0.0.0.0:${PORT} app_bridge:app\n\
BASH\n\
' && chmod +x /app/entrypoint.sh

# Healthcheck do Bridge
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=5 \
  CMD curl -fsS "http://127.0.0.1:${PORT}/health" || exit 1

EXPOSE 8080
CMD ["/bin/bash","-lc","/app/entrypoint.sh"]