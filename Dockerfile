# syntax=docker/dockerfile:1.7

ARG PYTHON_IMAGE=python:3.10-slim-bookworm
ARG DEBIAN_IMAGE=debian:bookworm-slim
ARG AZURE_CLI_DEBIAN_SUITE=bookworm

FROM ${PYTHON_IMAGE} AS python-runtime

RUN set -eux; \
    rm -f /usr/local/bin/pip /usr/local/bin/pip3 /usr/local/bin/pip3.* /usr/local/bin/wheel; \
    rm -rf /usr/local/lib/python*/site-packages/pip /usr/local/lib/python*/site-packages/pip-*.dist-info /usr/local/lib/python*/site-packages/wheel /usr/local/lib/python*/site-packages/wheel-*.dist-info; \
    rm -rf /usr/local/lib/python*/site-packages/setuptools/_vendor/wheel /usr/local/lib/python*/site-packages/setuptools/_vendor/wheel-*.dist-info; \
    find /usr/local -depth \( \
      \( -type d -a \( -name "__pycache__" -o -name "test" -o -name "tests" -o -name "idle_test" \) \) \
      -o \( -type f -a \( -name "*.pyc" -o -name "*.pyo" \) \) \
    \) -exec rm -rf '{}' +

FROM ${DEBIAN_IMAGE} AS base

ARG AZURE_CLI_DEBIAN_SUITE=bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN set -eux; \
    apt-get update; \
    apt-get upgrade -y --no-install-recommends; \
    apt-get install -y --no-install-recommends ca-certificates curl gpg libbz2-1.0 libexpat1 libffi8 liblzma5 libncursesw6 libreadline8 libsqlite3-0 libssl3 libuuid1 zlib1g; \
    install -m 0755 -d /etc/apt/keyrings; \
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg; \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg; \
    chmod go+r /etc/apt/keyrings/microsoft.gpg; \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ ${AZURE_CLI_DEBIAN_SUITE} main" > /etc/apt/sources.list.d/azure-cli.list; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends azure-cli curl gh jq; \
    /opt/az/bin/python3 -m pip install --no-cache-dir --no-compile --upgrade "urllib3==2.7.0"; \
    rm -f /opt/az/bin/pip /opt/az/bin/pip3 /opt/az/bin/pip3.* /opt/az/bin/wheel; \
    rm -rf /opt/az/lib/python*/site-packages/pip /opt/az/lib/python*/site-packages/pip-*.dist-info; \
    rm -rf /opt/az/lib/python*/site-packages/setuptools/_vendor/wheel /opt/az/lib/python*/site-packages/setuptools/_vendor/wheel-*.dist-info; \
    find /opt/az/lib/python*/site-packages -depth \( \
      \( -type d -a \( -name "__pycache__" -o -name "test" -o -name "tests" \) \) \
      -o \( -type f -a \( -name "*.pyc" -o -name "*.pyo" \) \) \
    \) -exec rm -rf '{}' +; \
    apt-get purge -y --auto-remove gpg; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --from=python-runtime /usr/local /usr/local

FROM base AS cli-binaries

ARG TARGETARCH
ARG DATABRICKS_CLI_VERSION=0.299.2
ARG YQ_VERSION=4.53.2

RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
      amd64) arch="amd64" ;; \
      arm64) arch="arm64" ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    mkdir -p /out; \
    databricks_file="databricks_cli_${DATABRICKS_CLI_VERSION}_linux_${arch}.zip"; \
    curl -fsSLo "/tmp/${databricks_file}" "https://github.com/databricks/cli/releases/download/v${DATABRICKS_CLI_VERSION}/${databricks_file}"; \
    curl -fsSLo /tmp/databricks_SHA256SUMS "https://github.com/databricks/cli/releases/download/v${DATABRICKS_CLI_VERSION}/databricks_cli_${DATABRICKS_CLI_VERSION}_SHA256SUMS"; \
    grep -F "${databricks_file}" /tmp/databricks_SHA256SUMS > /tmp/databricks.sha256; \
    cd /tmp; \
    sha256sum -c /tmp/databricks.sha256; \
    python3 -m zipfile -e "/tmp/${databricks_file}" /tmp/databricks; \
    install -m 0755 "$(find /tmp/databricks -type f -name databricks -print -quit)" /out/databricks; \
    yq_file="yq_linux_${arch}"; \
    curl -fsSLo "/tmp/${yq_file}" "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/${yq_file}"; \
    curl -fsSLo /tmp/yq_checksums "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/checksums"; \
    curl -fsSLo /tmp/yq_checksums_hashes_order "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/checksums_hashes_order"; \
    yq_sha256="$(python3 -c 'import sys; name = sys.argv[1]; order = [line.strip() for line in open("/tmp/yq_checksums_hashes_order", encoding="utf-8")]; field = order.index("SHA-256") + 1; print(next(line.split()[field] for line in open("/tmp/yq_checksums", encoding="utf-8") if line.split()[0] == name))' "${yq_file}")"; \
    printf '%s  %s\n' "${yq_sha256}" "${yq_file}" > /tmp/yq.sha256; \
    sha256sum -c /tmp/yq.sha256; \
    install -m 0755 "/tmp/${yq_file}" /out/yq; \
    /out/databricks -v; \
    /out/yq --version; \
    rm -rf /tmp/*

FROM base AS dbsqlcli

ARG DBSQLCLI_VERSION=0.3.3

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

RUN set -eux; \
    python3 -m venv /opt/dbsqlcli; \
    /opt/dbsqlcli/bin/python -m pip install --no-cache-dir --no-compile --only-binary=numpy,pandas,pyarrow,lz4,sqlalchemy "databricks-sql-cli==${DBSQLCLI_VERSION}"; \
    /opt/dbsqlcli/bin/python -m pip check; \
    /opt/dbsqlcli/bin/dbsqlcli --help >/dev/null; \
    find /opt/dbsqlcli -type d \( -name "__pycache__" -o -name "tests" -o -name "test" \) -prune -exec rm -rf '{}' +; \
    rm -f /opt/dbsqlcli/bin/pip /opt/dbsqlcli/bin/pip3 /opt/dbsqlcli/bin/pip3.*; \
    rm -rf /opt/dbsqlcli/lib/python*/site-packages/pip /opt/dbsqlcli/lib/python*/site-packages/pip-*.dist-info; \
    rm -rf /opt/dbsqlcli/lib/python*/site-packages/setuptools/_vendor/wheel /opt/dbsqlcli/lib/python*/site-packages/setuptools/_vendor/wheel-*.dist-info; \
    rm -rf /root/.cache /tmp/* /var/tmp/*

FROM base

LABEL org.opencontainers.image.title="GitHub Actions Databricks/Azure tools image" \
      org.opencontainers.image.description="Python slim Bookworm based job container with Azure CLI, Databricks CLI, dbsqlcli, GitHub CLI, yq, jq, and curl."

ENV PATH="/opt/dbsqlcli/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1

COPY --from=cli-binaries /out/databricks /usr/local/bin/databricks
COPY --from=cli-binaries /out/yq /usr/local/bin/yq
COPY --from=dbsqlcli /opt/dbsqlcli /opt/dbsqlcli

RUN set -eux; \
    ln -s /opt/dbsqlcli/bin/dbsqlcli /usr/local/bin/dbsqlcli; \
    rm -f /usr/local/bin/pip /usr/local/bin/pip3 /usr/local/bin/pip3.* /usr/local/bin/wheel; \
    rm -rf /usr/local/lib/python*/site-packages/pip /usr/local/lib/python*/site-packages/pip-*.dist-info /usr/local/lib/python*/site-packages/wheel /usr/local/lib/python*/site-packages/wheel-*.dist-info; \
    rm -rf /usr/local/lib/python*/site-packages/setuptools/_vendor/wheel /usr/local/lib/python*/site-packages/setuptools/_vendor/wheel-*.dist-info /opt/dbsqlcli/lib/python*/site-packages/setuptools/_vendor/wheel /opt/dbsqlcli/lib/python*/site-packages/setuptools/_vendor/wheel-*.dist-info /opt/az/lib/python*/site-packages/setuptools/_vendor/wheel /opt/az/lib/python*/site-packages/setuptools/_vendor/wheel-*.dist-info; \
    az version >/dev/null; \
    databricks -v; \
    dbsqlcli --help >/dev/null; \
    gh --version; \
    yq --version; \
    jq --version; \
    curl --version | head -n 1

CMD ["bash"]
