FROM python:3.12-slim-bookworm

WORKDIR /srv
COPY pyproject.toml ./
COPY src ./src
# psycopg2-binary: driver de PostgreSQL para Cloud SQL (sin licencias ni paquetes del sistema).
RUN pip install --no-cache-dir ".[postgres]"

# /data solo se usa con SQLite local; debe existir antes para que el volumen herede el dueno.
RUN useradd --create-home --uid 10001 ledger && install -d -o ledger /data
USER 10001

# Cloud Run inyecta PORT; en local se usa 8000.
ENV PORT=8000
EXPOSE 8000
CMD ["sh", "-c", "exec uvicorn ledger.asgi:app --host 0.0.0.0 --port ${PORT}"]
