# Infrastructure architecture

This repository holds the local environment and, later, the staging/production IaC for DistroCommerce.

## Request path

Client → (L4 load balancer: staging/prod only) → **Envoy Gateway** (Gateway API, TLS termination, JWT
validation, rate limiting, CORS) → services. All external traffic (api.*, auth.*, webhooks) enters through
Envoy, including requests to ZITADEL. Envoy injects the token `sub` into `X-User-ID`; workloads trust that
header (accepted debt: no NetworkPolicy, no service mesh yet).

## Workloads

Application services run in namespace `apps`. Each lives in its own repository and is deployed through the library chart
in `charts/service-lib/`. Services use gRPC between themselves; REST is served by each service behind Envoy.

## Decisions

| Area | Decision |
|---|---|
| Edge | Envoy Gateway (Gateway API), always deployed in the cluster in every environment |
| Identity | ZITADEL (OIDC); access tokens must be JWT (not opaque) so Envoy validates via JWKS |
| Issuer | identical in ZITADEL, Envoy SecurityPolicy and tokens (locally `http://auth.localtest.me`) |
| Deploy | Helm (library chart `charts/service-lib`); Argo CD later |
| Messaging | Kafka KRaft (no Zookeeper) |
| Mesh / CDN | none for now |
| WAF | undecided (prod only, none locally) |
| CNI / network isolation | default CNI, no Cilium, no NetworkPolicy (accepted debt, revisit in a hardening phase) |
| PostgreSQL | exactly 18.6 in every environment (RDS `auto_minor_version_upgrade=false`, bump all together) |
| Observability | OTel Collector, Prometheus, Grafana, Tempo, Loki everywhere; no Mimir, no Jaeger, no separate tools cluster |
| Local ingress | kind `extraPortMappings` (Mac 8080/8443 → NodePort 30080/30443), not cloud-provider-kind |
| Diagrams | English only, no version numbers (label is just "PostgreSQL") |
| Sizing targets (staging/prod) | 5,000 RPS steady / 20,000 burst, 99.95% availability, p95 100 ms, p99 300 ms |
| IaC | Terraform for staging/prod (and the ZITADEL Terraform provider in all envs); Makefile + Helm locally |

## Placement per environment

| Component | Local | Staging / production |
|---|---|---|
| Kubernetes | kind (default CNI) | EKS (Terraform) |
| L4 load balancer | none (Mac ports → Envoy) | NLB, TCP passthrough |
| Envoy Gateway + Gateway API | kind, ns `edge` | cluster, ns `edge` |
| cert-manager, external-dns | not needed | cluster |
| ZITADEL | kind, ns `auth`, `auth.localtest.me` | cluster, ns `auth` |
| ZITADEL's PostgreSQL | in kind, disposable | separate RDS (Multi-AZ in prod); ZITADEL Cloud is the alternative |
| Microservices | kind, ns `apps` | cluster, ns `apps` |
| Services' PostgreSQL, Redis, MongoDB, Kafka | docker-compose | RDS/Aurora, ElastiCache, Atlas or DocumentDB (open), MSK |
| Observability stack | kind, ns `observability` | cluster, ns `observability`; Tempo/Loki data in S3 |
| Secrets | `.env` / K8s Secrets | External Secrets Operator + AWS Secrets Manager |
| IaC / deploy | Makefile + Helm `values-local` | Terraform + Helm `values-staging/prod`, CI `helm upgrade --atomic` |
| Dev loop | Tilt or Skaffold (step 8, optional) | n/a |

Diagrams: `docs/diagrams/deployment-local.md` ("Deployment diagram: Local (kind + docker-compose)") and
`docs/diagrams/deployment-staging-production.md` ("Deployment diagram: Staging and Production (EKS + AWS
managed services)"). PNG/SVG renders are next to them.

## Rules and pitfalls

- ZITADEL masterkey: exactly 32 chars, created before the first install, never changed.
- `make reset` must clear both kind and compose data, otherwise ZITADEL `sub` values diverge from data keyed by `sub` in the service databases.
- Name ZITADEL's database Service `zitadel-postgres`: a Service named `postgres` would shadow the compose
  container for pods (compose containers resolve by name on the docker network `distro`).
- The project uses its own docker network `distro` (not kind's default `kind`) so parallel kind-based projects do not
  share a network or hostnames like `postgres`. kind picks it up from `KIND_EXPERIMENTAL_DOCKER_NETWORK`, an
  experimental kind variable that the Makefile exports; a manual `kind create cluster` needs it set too. Host ports
  8080/8443 and the store ports (5432, 6379, 27017, 9094) are still shared, so projects using the same ports cannot run
  at the same time.
- Envoy cannot reach `auth.localtest.me` from inside the cluster (resolves to 127.0.0.1): JWKS goes through
  an Envoy Gateway `Backend` pointing at the in-cluster ZITADEL Service, while the JWKS `uri` keeps the public host.
- Envoy tracing is off by default and defaults to 100% sampling when on: always set `samplingRate` explicitly.
- Kafka needs two listeners: `kafka:9092` for pods/containers, `localhost:9094` for the Mac.

## Open questions

- MongoDB: Atlas or DocumentDB. Version parity on staging/prod (MSK, DocumentDB lag upstream).
- When to move from Prometheus-with-disk to Mimir/Thanos or a tools cluster.
- WAF placement (prod).
- Container log shipping (stdout of pods → Loki) is not set up: logs only arrive via OTLP from services for now.
- Local HTTPS (port 443 listener, certificate) is not configured; the local issuer is plain HTTP.
- Where the Helm library chart is published once CI needs pinned versions (planned: an OCI registry).
