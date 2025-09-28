# =============================
# Dockerfile — Bridge + BotGestor + GeoIP + supervisord (auto-discovery)
# =============================
FROM python:3.11-slim

LABEL org.opencontainers.image.title="Typebot Bridge + BotGestor" \
      org.opencontainers.image.description="Bridge FastAPI + Bot Gestor com supervisord e GeoIP"

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH="/app" \
    PORT=8080 \
    GEOIP_PATH="/app/GeoLite2-City.mmdb"

# Caminho padrão informado (se não bater, resolvemos em runtime)
ENV DEFAULT_BRIDGE_DIR="/app/bot_gestor/bot_gestora/bot_gestao/bot_gestor/typebot_conection/Typebot-conecet/outro"

WORKDIR /app

# ---- Sistema
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc g++ make libpq-dev curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# ---- Dependências Python (um único requirements.txt NA RAIZ do deploy)
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt \
 && pip install --no-cache-dir supervisor gunicorn uvicorn

# ---- Código do projeto
COPY . /app

# ---- (Opcional) GeoIP
RUN curl -fsSL -o "${GEOIP_PATH}" \
    "https://github.com/P3TERX/GeoLite.mmdb/releases/latest/download/GeoLite2-City.mmdb" \
 || echo "⚠️ GeoIP não baixado; seguindo sem GeoIP"

# ---- Script de entrada: descobre diretórios, gera supervisord.conf e inicia
RUN bash -lc 'cat > /app/entrypoint.sh << "BASH"\n\
#!/usr/bin/env bash\n\
set -euo pipefail\n\
echo \"[entrypoint] pwd=$(pwd)\"\n\
echo \"[entrypoint] DEFAULT_BRIDGE_DIR=${DEFAULT_BRIDGE_DIR}\"\n\
\n\
# 1) Resolve BRIDGE_DIR (preferência: env BRIDGE_DIR, depois default, depois busca automática)\n\
BRIDGE_DIR=\"${BRIDGE_DIR:-}\"\n\
if [ -n \"${BRIDGE_DIR}\" ] && [ -f \"${BRIDGE_DIR}/app_bridge.py\" ]; then\n\
  echo \"[entrypoint] Usando BRIDGE_DIR (env): ${BRIDGE_DIR}\"\n\
else\n\
  if [ -f \"${DEFAULT_BRIDGE_DIR}/app_bridge.py\" ]; then\n\
    BRIDGE_DIR=\"${DEFAULT_BRIDGE_DIR}\"\n\
    echo \"[entrypoint] Usando DEFAULT_BRIDGE_DIR: ${BRIDGE_DIR}\"\n\
  else\n\
    echo \"[entrypoint] Buscando app_bridge.py automaticamente…\"\n\
    BRIDGE_DIR=$(python - <<\"PY\"\n\
import os, sys\n\
skip={\"node_modules\", \".git\", \"venv\", \".venv\", \"__pycache__\"}\n\
for root, dirs, files in os.walk(\"/app\", topdown=True):\n\
    dirs[:] = [d for d in dirs if d not in skip]\n\
    if \"app_bridge.py\" in files:\n\
        print(root)\n\
        sys.exit(0)\n\
print(\"\")\n\
PY\n\
)\n\
    if [ -z \"${BRIDGE_DIR}\" ]; then\n\
      echo \"❌ app_bridge.py não encontrado em lugar nenhum sob /app\"\n\
      find /app -maxdepth 4 -type d -print\n\
      exit 1\n\
    fi\n\
    echo \"[entrypoint] Encontrado: ${BRIDGE_DIR}\"\n\
  fi\n\
fi\n\
\n\
# 2) Define BOT_DIR e BRIDGE_BOT_DIR (irmão do app_bridge.py)\n\
BOT_DIR=\"${BRIDGE_BOT_DIR:-${BRIDGE_DIR}/bot_gesto}\"\n\
export BRIDGE_BOT_DIR=\"${BOT_DIR}\"\n\
export GEOIP_DB_PATH=\"${GEOIP_PATH}\"\n\
\n\
echo \"[entrypoint] BRIDGE_DIR=${BRIDGE_DIR}\"\n\
echo \"[entrypoint] BRIDGE_BOT_DIR=${BRIDGE_BOT_DIR}\"\n\
\n\
# 3) Logs úteis\n\
ls -la \"${BRIDGE_DIR}\" || true\n\
ls -la \"${BRIDGE_BOT_DIR}\" || true\n\
\n\
# 4) Checagem leve (avisa se faltar db.py/fb_google.py, mas não bloqueia)\n\
if [ ! -f \"${BRIDGE_BOT_DIR}/db.py\" ] || [ ! -f \"${BRIDGE_BOT_DIR}/fb_google.py\" ]; then\n\
  echo \"⚠️ Atenção: db.py ou fb_google.py não encontrados em ${BRIDGE_BOT_DIR} (o Bridge pode falhar no IMPORT).\"\n\
fi\n\
\n\
# 5) Gera supervisord.conf dinâmico\n\
cat > /app/supervisord.conf <<SUP\n\
[supervisord]\n\
nodaemon=true\n\
logfile=/dev/null\n\
pidfile=/tmp/supervisord.pid\n\
\n\
[program:bridge]\n\
directory=${BRIDGE_DIR}\n\
command=gunicorn -k uvicorn.workers.UvicornWorker -b 0.0.0.0:${PORT} app_bridge:app\n\
autostart=true\n\
autorestart=true\n\
startretries=3\n\
stdout_logfile=/dev/stdout\n\
stdout_logfile_maxbytes=0\n\
stderr_logfile=/dev/stderr\n\
stderr_logfile_maxbytes=0\n\
environment=PYTHONUNBUFFERED=\"1\",PYTHONDONTWRITEBYTECODE=\"1\",BRIDGE_BOT_DIR=\"${BRIDGE_BOT_DIR}\",GEOIP_DB_PATH=\"${GEOIP_DB_PATH}\"\n\
\n\
[program:bot]\n\
directory=${BRIDGE_BOT_DIR}\n\
command=python -u bot.py\n\
autostart=true\n\
autorestart=true\n\
startretries=3\n\
stdout_logfile=/dev/stdout\n\
stdout_logfile_maxbytes=0\n\
stderr_logfile=/dev/stderr\n\
stderr_logfile_maxbytes=0\n\
SUP\n\
\n\
# 6) Sobe supervisord (2 processos)\n\
exec supervisord -c /app/supervisord.conf\n\
BASH\n\
'\n\
 && chmod +x /app/entrypoint.sh

# ---- Healthcheck (ping no /health do Bridge)
HEALTHCHECK --interval=30s --timeout=5s --start-period=25s --retries=5 \
  CMD curl -fsS "http://127.0.0.1:${PORT}/health" || exit 1

EXPOSE 8080

# ---- Entrypoint
CMD ["/bin/bash", "-lc", "/app/entrypoint.sh"]