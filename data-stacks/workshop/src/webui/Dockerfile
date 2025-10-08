FROM ghcr.io/astral-sh/uv:python3.13-bookworm-slim

RUN groupadd -g 1000 app && useradd -u 1000 -g app -m app && mkdir -p /app && chown app:app /app

WORKDIR /app

ADD images.tgz /app/images/
RUN chown -R app:app /app/images

USER app
COPY --chown=1000:1000 .python-version dashboard.html main.py pyproject.toml uv.lock /app/
RUN uv sync --frozen

CMD ["uv", "run", "main.py"]
