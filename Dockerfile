# ──────────────────────────────────────────────────────────────
# AgriSense AI backend image (Django + ASGI for WebSocket chat)
# ──────────────────────────────────────────────────────────────
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# System deps for Pillow and MySQL client
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        default-libmysqlclient-dev build-essential pkg-config \
    && rm -rf /var/lib/apt/lists/*

COPY backend/agrisense_backend/requirements.txt /app/requirements.txt
COPY backend/agrisense_backend/requirements-prod.txt /app/requirements-prod.txt
COPY backend/agrisense_backend/requirements-ai.txt /app/requirements-ai.txt
ARG INSTALL_AI=false
RUN pip install --upgrade pip \
    && pip install -r requirements.txt -r requirements-prod.txt \
    && if [ "$INSTALL_AI" = "true" ]; then pip install -r requirements-ai.txt; fi

COPY backend/agrisense_backend /app

RUN python manage.py collectstatic --noinput || true

EXPOSE 8000

# Daphne serves both HTTP and WebSockets (production chat).
CMD ["daphne", "-b", "0.0.0.0", "-p", "8000", "agrisense_backend.asgi:application"]
