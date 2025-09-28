# =============================
# Dockerfile — Bridge (auto deps + auto path)
# =============================
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH="/app" \
    PORT=8080

WORKDIR /app

# Sistema básico
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc g++ make libpq-dev curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Copia projeto e o entrypoint
COPY . /app
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Instala dependências:
# 1) /app/requirements.txt
# 2) /app/Typebot-conecet/requirements.txt
# 3) /app/Typebot-conecet/outro/requirements.txt
# Se nenhum existir, instala um conjunto mínimo
RUN bash -lc 'set -e; \
found=0; \
for f in "/app/requirements.txt" "/app/Typebot-conecet/requirements.txt" "/app/Typebot-conecet/outro/requirements.txt"; do \
  if [ -f "$f" ]; then echo "[deps] Using $f"; pip install --no-cache-dir -r "$f"; found=1; break; fi; \
done; \
if [ "$found" = "0" ]; then \
  echo "[deps] No requirements.txt found. Installing minimal set..."; \
  pip install --no-cache-dir fastapi pydantic gunicorn uvicorn redis cryptography user-agents geoip2 requests SQLAlchemy psycopg2-binary prometheus_client python-dotenv aiogram; \
fi'

# Healthcheck (depende da sua rota /health no app)
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=5 \
  CMD curl -fsS "http://127.0.0.1:${PORT}/health" || exit 1

EXPOSE 8080
CMD ["/bin/bash","-lc","/app/entrypoint.sh"]