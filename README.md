# distrocommerce-infra

Infrastructure for DistroCommerce: the local environment (docker-compose stores, kind cluster with Envoy Gateway,
ZITADEL and the observability stack), the shared Helm library chart, and later Terraform for staging and production.

Start with `CLAUDE.md`, then `docs/architecture.md`, `docs/local-environment.md` and `docs/STATUS.md`.

```
compose/   docker-compose stores (PostgreSQL, Redis, MongoDB, Kafka KRaft)
kind/      kind cluster config
k8s/       Envoy Gateway, ZITADEL, observability values and manifests, dev test apps
charts/    Helm library chart service-lib
terraform/ staging and production (later)
docs/      architecture, runbook, status, diagrams
```
