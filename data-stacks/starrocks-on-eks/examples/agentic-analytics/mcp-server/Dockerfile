FROM python:3.12-slim

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /app

COPY pyproject.toml .
RUN uv sync --frozen --no-dev --no-install-project

EXPOSE 8000
CMD ["uv", "run", "mcp-server-starrocks", "--mode", "streamable-http", "--host", "0.0.0.0", "--port", "8000"]
