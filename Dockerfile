# =============================
# Dockerfile — Bridge + Bot (supervisord, auto-deps)
# =============================
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH="/app" \
    PORT=8080 \
    BRIDGE_BOT_DIR="/app/bot_gesto"

WORKDIR /app

# Sistema básico
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc g++ make libpq-dev curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Copia projeto
COPY . /app

# Instala dependências:
# tenta, em ordem:
# 1) /app/requirements.txt
# 2) /app/Typebot-conecet/requirements.txt
# 3) /app/Typebot-conecet/outro/requirements.txt
# 4) /app/bot_gesto/requirements.txt
# fallback: instala um conjunto mínimo
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
  pip install --no-cache-dir fastapi pydantic gunicorn uvicorn redis cryptography user-agents geoip2 requests SQLAlchemy psycopg2-binary prometheus_client python-dotenv aiogram; \
fi; \
pip install --no-cache-dir supervisor \
'

# Gera supervisord.conf (2 processos: bridge + bot)
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
"directory=/app/bot_gesto" \
"command=python -u bot.py" \
"autostart=true" \
"autorestart=true" \
"startretries=3" \
"stdout_logfile=/dev/stdout" \
"stdout_logfile_maxbytes=0" \
"stderr_logfile=/dev/stderr" \
"stderr_logfile_maxbytes=0" \
> /app/supervisord.conf

# Healthcheck (usa /health do bridge)
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=5 \
  CMD curl -fsS "http://127.0.0.1:${PORT}/health" || exit 1

EXPOSE 8080
CMD ["supervisord", "-c", "/app/supervisord.conf"]