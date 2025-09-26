# Dockerfile for using Glue in Datahub actions runner with no runtime pip installation.

FROM docker.io/acryldata/datahub-actions:v1.2.0@sha256:6d02af7d4a0f7689fe00e1feb8869380397016b191f5f786772bdb2ecd0c0763

USER root

RUN apt update && apt install -y vim

# We install required runtime packages system wide. note that 1.0.0 is used by 1.2.0 for some reason.
RUN uv pip install --system package-name --upgrade pip wheel setuptools
RUN uv pip install --system package-name 'acryl-datahub[datahub-rest,datahub-kafka,iceberg]==1.0.0' &&  uv pip install --system package-name 'pyiceberg[glue]<=0.6.1'

RUN chown -R datahub:datahub /home/datahub

USER datahub

# We then install runtime packages in the datahub user venv
RUN uv pip install --upgrade pip wheel setuptools

RUN uv pip install 'acryl-datahub[datahub-rest,datahub-kafka,iceberg]==1.2.0' &&  uv pip install 'pyiceberg[glue]<=0.6.1' 's3fs'

# https://github.com/datahub-project/datahub/pull/14766
# RUN uv pip install 'pyiceberg[glue]<=0.6.1'

# set everything to offline and use system packages
ENV UV_SYSTEM_PYTHON=1
ENV UV_SYSTEM_SITE_PACKAGES=1
ENV UV_OFFLINE=1


# test configuration
# pipeline_name: urn:li:dataHubIngestionSource:bbd75984-c1cc-46e0-bbd2-905768d667f7
# run_id: 40c25c7a-0f8a-4bb1-a0e0-d09f0ea70a77
# source:
#   config:
#     catalog:
#       workshop_catalog:
#         region_name: us-west-2
#         s3.region: us-west-2
#         type: glue
#     table_pattern:
#       allow:
#       - data-on-eks
#   type: iceberg

#   datahub ingest run -c /tmp/test.yaml --report-to /tmp/datahub/logs/7645426c-1251-4fd6-a85d-c402e25463c3/artifacts/ingestion_report.json