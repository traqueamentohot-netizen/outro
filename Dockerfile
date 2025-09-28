# ========== Dockerfile (Minimal: Bridge) ==========
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 PORT=8080 PYTHONPATH="/app"

# Caminho exato (Linux) onde está o app_bridge.py (o que você informou)
ENV BRIDGE_DIR="/app/bot_gestor/bot_gestora/bot_gestao/bot_gestor/typebot_conection/Typebot-conecet/outro"
# Pasta do bot (irmã do app_bridge.py)
ENV BRIDGE_BOT_DIR="${BRIDGE_DIR}/bot_gesto"

WORKDIR /app

# Sistema básico
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc g++ make libpq-dev curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Dependências (um único requirements.txt na raiz do deploy)
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt \
 && pip install --no-cache-dir gunicorn uvicorn

# Código
COPY . /app

# CMD: valida e sobe o Bridge
CMD ["/bin/bash","-lc", "\
  echo '[CMD] PORT='${PORT}; \
  if [ ! -f '${BRIDGE_DIR}/app_bridge.py' ]; then \
    echo '❌ app_bridge.py não encontrado em: ${BRIDGE_DIR}'; \
    echo '[busca] procurando em /app (até 4 níveis)'; \
    find /app -maxdepth 4 -name app_bridge.py -printf '→ %h/app_bridge.py\n' || true; \
    exit 1; \
  fi; \
  export BRIDGE_BOT_DIR='${BRIDGE_BOT_DIR}'; \
  echo '[CMD] BRIDGE_DIR='${BRIDGE_DIR}; \
  echo '[CMD] BRIDGE_BOT_DIR='${BRIDGE_BOT_DIR}; \
  ls -la '${BRIDGE_DIR}'; \
  ls -la '${BRIDGE_BOT_DIR}' || true; \
  exec gunicorn -k uvicorn.workers.UvicornWorker --chdir '${BRIDGE_DIR}' -b 0.0.0.0:${PORT} app_bridge:app \
"]