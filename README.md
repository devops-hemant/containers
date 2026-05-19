# GitHub Actions Tools Image declis(Data Engineering CLIs)

Small Python slim / Debian Bookworm based job-container image for GitHub Actions workflows that need:

- Azure CLI (`az`)
- Databricks CLI (`databricks`)
- Databricks SQL CLI (`dbsqlcli`)
- GitHub CLI (`gh`)
- `yq`
- `jq`
- `curl`

This is meant to be used as a GitHub Actions job container with `jobs.<job>.container`. It is not a self-hosted GitHub Actions runner daemon image.

## Why This Base

The image uses `python:3.10-slim-bookworm` because Microsoft supports Debian 12 for Azure CLI packages and `databricks-sql-cli==0.3.3` pins older Python dependencies. Python 3.10 is still maintained and has wheels for the pinned `dbsqlcli` dependency set, so the build avoids compilers and source builds.

The official Azure CLI container now uses Azure Linux 3.0 and is a good base for many images, but in this specific tool mix it pushes `dbsqlcli` into source-building old NumPy on Python 3.12. Debian 12's default Python 3.11 still lacks a wheel for `pandas==1.3.4`, so this Dockerfile uses Python 3.10. The old Alpine-based Azure CLI image is no longer supported, so it is intentionally avoided.

Azure CLI and `dbsqlcli` bring Python runtimes/dependencies, so they dominate the final size. The Dockerfile keeps the final image lean by:

- starting from `python:3.10-slim-bookworm` and installing Azure CLI from Microsoft's apt repository;
- installing packages with `--no-install-recommends`;
- downloading Databricks CLI, GitHub CLI, and `yq` as standalone binaries;
- verifying downloaded Databricks CLI, GitHub CLI, and `yq` assets with upstream SHA256 files;
- installing `dbsqlcli` in an isolated virtual environment;
- forcing binary Python wheels for the heavy compiled dependencies so compilers never enter the build;
- removing pip and temporary caches from build layers.

## Build

```bash
docker build --provenance=false -t gha-runner-tools:local .
```

For a pushed multi-architecture image:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --provenance=false \
  -t ghcr.io/YOUR_ORG/gha-runner-tools:latest \
  --push .
```

The main versions are build args:

```bash
docker build \
  --provenance=false \
  --build-arg PYTHON_IMAGE=python:3.10-slim-bookworm \
  --build-arg AZURE_CLI_DEBIAN_SUITE=bookworm \
  --build-arg DATABRICKS_CLI_VERSION=0.299.2 \
  --build-arg DBSQLCLI_VERSION=0.3.3 \
  --build-arg GH_CLI_VERSION=2.92.0 \
  --build-arg YQ_VERSION=4.53.2 \
  -t gha-runner-tools:local .
```

## Smoke Test

```bash
docker run --rm gha-runner-tools:local bash -lc '
  az version >/dev/null &&
  databricks -v &&
  dbsqlcli --help >/dev/null &&
  gh --version &&
  yq --version &&
  jq --version &&
  curl --version | head -n 1
'
```

## Vulnerability Scan

Use the scanner your org standardizes on. Two common options:

```bash
trivy image --severity HIGH,CRITICAL --exit-code 1 gha-runner-tools:local
```

```bash
docker scout cves gha-runner-tools:local
```

Current local arm64 build result with Docker Scout for HIGH/CRITICAL only:

- image tag: `gha-runner-tools:local`
- local Docker image size: `1.12GB`
- Scout analyzed size: `211MB`
- package count: `677`
- vulnerability count: `0 critical`, `14 high`

The remaining high findings are currently constrained by upstream packages:

- Go `stdlib`, `golang.org/x/net`, and `github.com/docker/cli` findings are from standalone Go binaries.
- Debian `gnutls28` findings currently report no fixed Bookworm package.
- `sqlparse==0.4.4` is pinned by `databricks-sql-cli==0.3.3` through `<0.5.0`.

Rebuild regularly to pick up Debian, Microsoft Azure CLI, GitHub CLI, Databricks CLI, and `yq` fixes as they are published.

## GitHub Actions Usage

```yaml
jobs:
  databricks-deploy:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/YOUR_ORG/gha-runner-tools:latest
    steps:
      - uses: actions/checkout@v4

      - name: Verify tools
        run: |
          az version
          databricks -v
          dbsqlcli --help
          gh --version
          yq --version
          jq --version
          curl --version
```

For Databricks authentication, pass `DATABRICKS_HOST` and `DATABRICKS_TOKEN` as GitHub Actions secrets. For Azure, prefer OIDC with `azure/login` before running `az` commands.

## References

- [Azure CLI Docker container docs](https://learn.microsoft.com/en-us/cli/azure/run-azure-cli-docker)
- [Azure CLI Linux install docs](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux)
- [GitHub CLI install docs](https://github.com/cli/cli/blob/trunk/docs/install_linux.md)
- [Databricks CLI install docs](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/cli/install)
- [Databricks SQL CLI on PyPI](https://pypi.org/project/databricks-sql-cli/)
- [yq releases](https://github.com/mikefarah/yq/releases)
