# =============================
# Dockerfile — Bridge + BotGestor + GeoIP + supervisord
# =============================
FROM python:3.11-slim

LABEL org.opencontainers.image.title="Typebot Bridge + BotGestor" \
      org.opencontainers.image.description="Bridge FastAPI + Bot Gestor com supervisord e GeoIP"

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8080 \
    PYTHONPATH="/app" \
    GEOIP_PATH="/app/GeoLite2-City.mmdb"

# Caminhos (case-sensitive) conforme você informou
ENV BRIDGE_DIR="/app/bot_gestor/bot_gestora/bot_gestao/bot_gestor/typebot_conection/Typebot-conecet/outro"
ENV BOT_DIR="${BRIDGE_DIR}/bot_gesto"
ENV BRIDGE_BOT_DIR="${BOT_DIR}"
ENV GEOIP_DB_PATH="${GEOIP_PATH}"

WORKDIR /app

# ---- Sistema
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc g++ make libpq-dev curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# ---- Dependências Python (um único requirements.txt na raiz)
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt \
 && pip install --no-cache-dir supervisor gunicorn uvicorn

# ---- Código
COPY . /app

# ---- Validação precoce de caminhos (falha o build se algo não bater)
RUN bash -lc 'test -f "${BRIDGE_DIR}/app_bridge.py" || (echo "❌ app_bridge.py não encontrado em: ${BRIDGE_DIR}" && ls -la "${BRIDGE_DIR}" || true && exit 1)' \
 && bash -lc 'test -d "${BOT_DIR}" || (echo "❌ Pasta do bot não encontrada em: ${BOT_DIR}" && ls -la "${BRIDGE_DIR}" || true && exit 1)'

# ---- GeoIP (opcional)
RUN curl -fsSL -o "${GEOIP_PATH}" \
    "https://github.com/P3TERX/GeoLite.mmdb/releases/latest/download/GeoLite2-City.mmdb" \
 || echo "⚠️ GeoIP não baixado; seguindo sem GeoIP"

# ---- Healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=5 \
  CMD curl -fsS "http://127.0.0.1:${PORT}/health" || exit 1

EXPOSE 8080

# ---- supervisord.conf inline (2 processos: Bridge + Bot)
RUN printf "%s\n" \
"[supervisord]" \
"nodaemon=true" \
"logfile=/dev/null" \
"pidfile=/tmp/supervisord.pid" \
"" \
"[program:bridge]" \
"directory=%(ENV_BRIDGE_DIR)s" \
"command=gunicorn -k uvicorn.workers.UvicornWorker -b 0.0.0.0:%(ENV_PORT)s app_bridge:app" \
"autostart=true" \
"autorestart=true" \
"startretries=3" \
"stdout_logfile=/dev/stdout" \
"stdout_logfile_maxbytes=0" \
"stderr_logfile=/dev/stderr" \
"stderr_logfile_maxbytes=0" \
"environment=PYTHONUNBUFFERED=\"1\",PYTHONDONTWRITEBYTECODE=\"1\",BRIDGE_BOT_DIR=\"%(ENV_BRIDGE_BOT_DIR)s\",GEOIP_DB_PATH=\"%(ENV_GEOIP_DB_PATH)s\"" \
"" \
"[program:bot]" \
"directory=%(ENV_BOT_DIR)s" \
"command=python -u bot.py" \
"autostart=true" \
"autorestart=true" \
"startretries=3" \
"stdout_logfile=/dev/stdout" \
"stdout_logfile_maxbytes=0" \
"stderr_logfile=/dev/stderr" \
"stderr_logfile_maxbytes=0" \
> /app/supervisord.conf

CMD ["supervisord", "-c", "/app/supervisord.conf"]