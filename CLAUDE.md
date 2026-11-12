# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this repo is
`distrocommerce-infra` holds the infrastructure for DistroCommerce: the local environment (docker-compose stores plus a
kind cluster with Envoy Gateway, ZITADEL and the observability stack), the shared Helm library chart, and later the
Terraform for staging and production. Application services live in their own repositories and are only deployed from here
through the library chart.

Read first: `docs/architecture.md` (decisions, placement per environment, pitfalls, open questions),
`docs/local-environment.md` (step-by-step runbook), `docs/STATUS.md` (progress), `docs/diagrams/`.

## Target
Client → Envoy Gateway (Gateway API; always deployed in the cluster, in every environment; JWT validation; injects the
token `sub` as `X-User-ID`) → services. ZITADEL is the OIDC provider. Backing stores: PostgreSQL, Redis, MongoDB,
Kafka (KRaft). Observability: OTel Collector, Prometheus, Grafana, Tempo, Loki.
Local: kind runs Envoy, ZITADEL (with its own PostgreSQL), the services and the observability stack; docker-compose runs
only the stateful stores. Staging/production: one EKS cluster plus AWS managed stores.

## Layout
- `compose/`: docker-compose stores (PostgreSQL, Redis, MongoDB, Kafka KRaft)
- `kind/`: kind cluster config
- `k8s/`: Envoy Gateway, ZITADEL and observability values and manifests; `k8s/dev/` holds throwaway test apps
- `charts/service-lib/`: Helm library chart used by service repositories
- `terraform/`: staging and production (not started)
- `docs/`: architecture, runbook, status, diagrams
- `Makefile`: `doctor`, `up`, `reset` and per-component targets

## Fixed decisions (do not reopen unless asked)
- Local ingress uses kind `extraPortMappings` (host 8080/8443 to NodePort 30080/30443). No cloud-provider-kind.
- Envoy Gateway is pinned to v1.9.3. PostgreSQL is exactly 18.6 everywhere. Local stores: Redis 8.10-alpine,
  MongoDB 9.0, Kafka 4.4.0. Pin every chart version; never deploy `latest`.
- No Cilium, NetworkPolicy, service mesh or CDN for now (accepted debt). Tempo only (no Jaeger), no Mimir, no separate
  tools cluster. Helm now, Argo CD later. Terraform for staging/production and for ZITADEL configuration.
- ZITADEL access tokens must be JWT. The issuer must be identical in ZITADEL, the Envoy SecurityPolicy and the tokens
  (`http://auth.localtest.me:8080` locally).
- Diagrams: English only, no version numbers, Mermaid sources in `docs/diagrams/`.
- Developer machine: macOS with Docker Desktop. `kcat` is intentionally not used.
- Helm 4 is the baseline (v4.x). Use `--rollback-on-failure` instead of `--atomic` and `--force-replace` instead of `--force`.

## How to work here
- Follow the runbook one step at a time and run a step's checks before starting the next.
- The configs are drafts that have never been run. Before relying on a Helm value key run `helm show values <chart>` for the
  pinned chart version; before relying on a CRD field check the docs or `kubectl explain`. Say plainly when something is
  unverified instead of guessing. Steps 1-7 were run and verified (see `docs/STATUS.md`): the library chart with a
  stand-in (`k8s/dev/lib-test`) and with the first real service, `profile-service`. Step 8 (`make up`/`reset`) is not.
- Images must have linux/arm64 builds (Apple silicon): check with `docker manifest inspect` before pinning a new tag.
- Makefile recipes need tab indentation. Start order matters: the docker network `distro` (`DOCKER_NET` in the Makefile, passed to kind via `KIND_EXPERIMENTAL_DOCKER_NETWORK`) must exist before compose (see `make up`).
- Never commit secrets (`.env` is ignored). Passwords in local manifests are development-only.
- All repository content, comments and commit messages are in English.
