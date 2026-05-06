FROM python:3.12-slim

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /app

COPY pyproject.toml .
RUN uv sync --frozen --no-dev --no-install-project

COPY seed_data.py .

CMD ["uv", "run", "python", "seed_data.py"]
