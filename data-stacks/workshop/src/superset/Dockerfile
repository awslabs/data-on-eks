
# The official image is bugged because it's missing the postgresql client binary.
#
# https://github.com/apache/superset/discussions/31431
# https://superset.apache.org/docs/installation/docker-builds/#building-your-own-production-docker-image

FROM apachesuperset.docker.scarf.sh/apache/superset:5.0.0

USER root

RUN . /app/.venv/bin/activate && uv pip install psycopg2-binary

USER superset