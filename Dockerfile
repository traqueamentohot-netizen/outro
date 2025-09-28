# =============================
# Dockerfile — Bridge + Bot (supervisord + diagnóstico)
# =============================
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="/app" PORT=8080 \
    BRIDGE_BOT_DIR="/app/bot_gesto"

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc g++ make libpq-dev curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Projeto + scripts
COPY . /app
COPY run_bot.sh /app/run_bot.sh
RUN chmod +x /app/run_bot.sh

# Dependências (procura requirements em locais comuns; fallback instala mínimo)
RUN bash -lc '\
set -e; found=""; \
for f in \
  "/app/requirements.txt" \
  "/app/Typebot-conecet/requirements.txt" \
  "/app/Typebot-conecet/outro/requirements.txt" \
  "/app/bot_gesto/requirements.txt" \
; do \
  if [ -f "$f" ]; then echo "[deps] Using $f"; pip install --no-cache-dir -r "$f"; found=1; break; fi; \
done; \
if [ -z "$found" ]; then \
  echo "[deps] No requirements.txt found. Installing minimal set..."; \
  pip install --no-cache-dir fastapi pydantic gunicorn uvicorn redis cryptography user-agents geoip2 requests SQLAlchemy psycopg2-binary prometheus_client python-dotenv aiogram alembic; \
fi; \
pip install --no-cache-dir supervisor'

# supervisord: 2 processos (bridge + bot)
RUN printf "%s\n" \
"[supervisord]" \
"nodaemon=true" \
"logfile=/dev/null" \
"pidfile=/tmp/supervisord.pid" \
"" \
"[program:bridge]" \
"directory=/app" \
"command=gunicorn -k uvicorn.workers.UvicornWorker -b 0.0.0.0:${PORT} app_bridge:app" \
"autostart=true" \
"autorestart=true" \
"startretries=3" \
"stdout_logfile=/dev/stdout" \
"stdout_logfile_maxbytes=0" \
"stderr_logfile=/dev/stderr" \
"stderr_logfile_maxbytes=0" \
"environment=PYTHONUNBUFFERED=\"1\",PYTHONDONTWRITEBYTECODE=\"1\",BRIDGE_BOT_DIR=\"/app/bot_gesto\"" \
"" \
"[program:bot]" \
"directory=/app" \
"command=/bin/bash -lc /app/run_bot.sh" \
"autostart=true" \
"autorestart=true" \
"startretries=3" \
"stdout_logfile=/dev/stdout" \
"stdout_logfile_maxbytes=0" \
"stderr_logfile=/dev/stderr" \
"stderr_logfile_maxbytes=0" \
> /app/supervisord.conf

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=5 \
  CMD curl -fsS "http://127.0.0.1:${PORT}/health" || exit 1

EXPOSE 8080
CMD ["supervisord", "-c", "/app/supervisord.conf"]