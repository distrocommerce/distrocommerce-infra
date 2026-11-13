# Local environment status

Update this file as steps are completed. Everything below was designed in a chat session and **not yet
run end to end**; configs for steps 1-7 are drafts to verify (chart value keys especially).

| Step | What | Status |
|---|---|---|
| 0 | Tools, Docker Desktop resources, repo skeleton | done |
| 1 | docker-compose stores | done (2026-11-08) |
| 2 | kind cluster with extraPortMappings | done (2026-11-08) |
| 3 | Envoy Gateway v1.9.3 + Gateway | done (2026-11-08) |
| 4 | ZITADEL + its PostgreSQL | done (2026-11-09) |
| 5 | JWT SecurityPolicy | done (2026-11-09) |
| 6 | Observability stack | done (2026-11-10) |
| 7 | Library chart and first service deployment | done (2026-11-12) |
| 8 | Automation (`make up/reset`, Tilt or Skaffold) | Makefile drafted, Tilt/Skaffold not started |

## Step 1 notes (2026-11-08)
- Image tags confirmed with `docker manifest inspect` (all have linux/arm64): `postgres:18.6`, `redis:8.10-alpine`,
  `mongo:9.0`, `apache/kafka:4.4.0`. Running versions: PostgreSQL 18.6, Redis 8.10.3, MongoDB 9.0.4, Kafka 4.4.0.
- `make infra-up`: all four services `healthy`. Databases/roles created: inventory, notification, order, payment,
  product, profile. Redis PONG, Mongo ping ok, Kafka topic list ok (empty). `postgres`, `redis`, `mongo`, `kafka`
  resolve on the docker network `kind`.
- Fixed: `postgres-init/01-databases.sh` failed on `CREATE ROLE order` (reserved word); identifiers are now quoted.
- Follow-up: the Kafka healthcheck uses `kafka-broker-api-versions.sh`, deprecated in 4.4 in favour of
  `kafka-cluster.sh api-versions`. It still works.

## Docker network rename (2026-11-08)
- The project now uses its own docker network `distro` instead of `kind` (compose services, `DOCKER_NET` in the
  Makefile, exported to kind as `KIND_EXPERIMENTAL_DOCKER_NETWORK`). Step 1 was verified on the old `kind` network;
  rerun its checks (with `--network distro`) after the next `make infra-up`.

## Step 2 notes (2026-11-08)
- Host ports changed from 80/443 to 8080/8443 (`kind/kind.yaml`, `make doctor`, docs). Local URLs and the ZITADEL
  issuer now need `:8080`; steps 3-6 files are not updated yet.
- `make cluster-up` with kind v0.31.0 (node image `kindest/node:v1.35.0`, kind's default, not pinned in `kind.yaml`).
  kind printed the expected `KIND_EXPERIMENTAL_DOCKER_NETWORK` warning and put `distro-control-plane` on the `distro`
  network next to the four stores.
- Node Ready, all kube-system and local-path-storage pods Running. Ports: `127.0.0.1:8080->30080`, `127.0.0.1:8443->30443`.
- A pod reached `postgres:5432`, `redis:6379`, `mongo:27017` and `kafka:9092` by name.

## Step 3 notes (2026-11-08)
- `make edge-up`: release `eg` deployed (`gateway-helm-v1.9.3`, app v1.9.3), 18 Gateway API / Envoy Gateway CRDs.
  GatewayClass `eg` Accepted, Gateway `edge/public` Programmed.
- Envoy Proxy image (Envoy Gateway default, not pinned by us): `envoyproxy/envoy:distroless-v1.39.5`.
- Verified: the EnvoyProxy nodePort patch (Service `80:30080/TCP`) and the Backend API key
  `config.envoyGateway.extensionApis.enableBackend` (in the `envoy-gateway-config` ConfigMap; the controller watches
  `Backend`). A real `Backend` object is first used in step 4.
- `k8s/dev/echo.yaml`: HTTPRoute Accepted/ResolvedRefs, `curl http://echo.localtest.me:8080/` → 200 "hello from envoy";
  echo deleted afterwards.

## Step 4 notes (2026-11-09)
- Issuer switched to `http://auth.localtest.me:8080`: ZITADEL `ExternalPort: 8080`, `k8s/dev/jwt-policy.yaml`
  issuer and JWKS uri, runbook URLs, `CLAUDE.md` and `docs/architecture.md`.
- Chart pinned: `ZITADEL_CHART_VERSION ?= 10.5.0` (ZITADEL v4.19.2). `helm template` with our values passes the chart
  schema; key placement matches `helm show values`.
- `make auth-up`: zitadel, zitadel-login and zitadel-postgres-0 (PostgreSQL 18.6) Running; init and setup jobs Complete.
  HTTPRoute Accepted/ResolvedRefs; Backend `apps/zitadel-jwks` created (reports no status; proven by the JWKS fetch in step 5).
- Discovery: issuer, jwks_uri, token and authorize endpoints all on `http://auth.localtest.me:8080`; `/oauth/v2/keys` 200.
  Console authorize redirects to `/ui/v2/login/loginname` on `:8080` (the Login UI sends `Host` without the port, but
  redirects keep it).
- Chart also creates machine user `iam-admin` (IAM_OWNER) with key in secret `auth/iam-admin` and a PAT in
  `auth/iam-admin-pat`.
- Console (manual): admin login works; project `distrocommerce` created; service account `local-test` (Users →
  Service Accounts; the client ID is the user name) with access token type JWT and a client secret.
- Client-credentials token with scope `urn:zitadel:iam:org:project:id:<project id>:aud`: JWT (`eyJ…`),
  `iss` = `http://auth.localtest.me:8080`, `aud` contains the project ID, `sub` = service account ID.
  Project and service account IDs change after `make reset`.

## Step 5 notes (2026-11-09)
- SecurityPolicy fields (`issuer`, `audiences`, `remoteJWKS.uri/backendRefs`, `claimToHeaders`) checked with
  `kubectl explain` on the v1.9.3 CRD. Policy Accepted; Backend `apps/zitadel-jwks` reports Accepted once referenced.
- JWKS fetched through the Backend (cluster host `zitadel.auth.svc.cluster.local`). One fetch failed right after the
  policy was applied ("cluster ... is not configured", startup race); later fetches succeeded.
- Results: no token → 401; garbage token → 401; tampered signature → 401 "Jwt verification fails"; valid token → 200
  with `X-User-Id` = service account `sub`; client-supplied `X-User-ID: hacker` overwritten with the real `sub`.
- Audiences (set on the live policy, not committed): correct project ID → 200; wrong ID → 403
  "Audiences in Jwt are not allowed". The test policy in `k8s/dev/jwt-policy.yaml` sets no audiences (the project ID
  changes after `make reset`); the library chart's `auth.audiences` is what services use.
- Test resources (whoami, jwt-zitadel) deleted afterwards.

## Step 6 notes (2026-11-10)
- GitHub Pages chart indexes downloaded at ~10 KB/s, so `helm repo add/update` never finished. All four charts now
  come from OCI on ghcr.io, pinned: kube-prometheus-stack 93.1.1, Tempo 3.2.1 (grafana-community; `grafana/tempo` is
  frozen at 1.24.4), Loki 21.1.1, OpenTelemetry Collector 0.178.2. The `obs-up` guard now requires every version.
- Values checked with `helm show values` and `helm template`: Loki filesystem/tsdb v13 config correct; Tempo keys
  unchanged in 3.2.1 (its default Jaeger receivers must stay: nulling them breaks the chart's Service template);
  collector 0.163 renamed exporters to `otlp_grpc`/`otlp_http` (values updated).
- First install failed: Prometheus Operator v0.95.1 (kps default) has amd64-only images. Pinned operator and
  config-reloader to v0.95.2. All other images in the stack have arm64 builds.
- Running: Prometheus v3.16.0, Grafana 13.3.0, Tempo 3.1.1, Loki 3.7.9, collector 0.163.2. Grafana at
  `http://grafana.localtest.me:8080`; Prometheus, Tempo and Loki data sources healthy. Removed the Alertmanager data
  source kps adds by default (`grafana.sidecar.datasources.alertmanager.enabled: false`).
- Pipeline: telemetrygen (service `step6-check`) → collector → 14 traces in Tempo, 27 log lines in Loki (OTLP `/otlp`),
  metric `gen` in Prometheus (remote write), all queried through Grafana.
- Envoy tracing enabled (`samplingRate: 100`, OpenTelemetry to `observability/otel-collector:4317`, no ReferenceGrant
  needed); requests through Envoy appear in Tempo as `public.edge` / `ingress`.
- Not set up: container stdout log shipping (Alloy or a filelog DaemonSet, decide later).

## Step 7 notes, part 1: library chart (2026-11-11)
- `charts/service-lib` 0.2.0: auth is on unless `auth.enabled: false` (a missing value used to mean no policy);
  `auth.issuer` and `auth.audiences` are required when on; `jwksUri`, `jwksBackend` and `jwksBackendPort` have
  defaults; the Deployment sets `OTEL_SERVICE_NAME` and `OTEL_EXPORTER_OTLP_ENDPOINT` (overridable through `env`).
- Bug found by a server-side dry run: a numeric project ID was rendered as a YAML integer and the SecurityPolicy CRD
  rejected it. An unquoted 18-digit ID can also lose float64 precision, so the chart now rejects non-string audiences
  and renders them quoted.
- Render checks: missing audiences, missing issuer or a missing `auth` block fail with a message; `auth.enabled: false`
  renders no policy; `env` overrides the OTel defaults.
- Stand-in deployed with `k8s/dev/lib-test` (traefik/whoami, release `libtest`): pod Running with probes on `/health`,
  HTTPRoute and SecurityPolicy Accepted, OTel env present. No token → 401, garbage token → 401, valid token → 200 with
  `X-User-Id` = sub, forged `X-User-ID` overwritten, wrong audience (via helm upgrade) → 403. Uninstalled afterwards.
- Part 2 below: the real service.

## Step 7 notes, part 2: first service (2026-11-12)
- `profile-service` (separate repository, Go 1.27.3): skeleton reviewed and fixed (image tag gets a `-dirty-<hash>`
  suffix for uncommitted trees, `/readyz` DB ping 800 ms below the 1 s probe timeout, values split). Unit tests,
  golangci-lint and the store test against the compose PostgreSQL pass.
- `make db-secrets` created `apps/profile-db`. Image `profile:<sha>` builds for arm64, runs as 65532:65532, ~35 MB.
- `make image kind-load deploy`: release `profile` in `apps`, pod Running, HTTPRoute and SecurityPolicy Accepted
  (audience rendered as a string). Migration `0001_create_profiles` applied.
- Through Envoy on `api.localtest.me:8080/v1/users/me`: no token → 401; valid token → 404 problem+json
  `profile_not_found`; after inserting a profile row for the service account `sub` → 200 with the profile.
  Paths outside `/v1/users` on the same host → 404 from Envoy.
- Tracing: one trace from Envoy (`ingress`, router) through `GET /v1/users/me` to pgx (`pool.acquire`, SELECT);
  the service logs the same `trace_id`. Tempo search needs a time range; use TraceQL in Grafana.
- Metrics: `job="profile"` in Prometheus via the collector: `http_server_request_duration_seconds` (with `http_route`,
  `http_response_status_code`), request/response body sizes, `db_client_operation_duration_seconds`, `pgxpool_*`.
  The request counts matched the test requests (one 404, one 200).

## Dashboards (2026-11-12)
- `k8s/observability/dashboards/service-overview.json` (uid `service-overview`), applied as a ConfigMap by
  `make dashboards` (called from `obs-up`). One generic dashboard for all services, selected by `job`: RED metrics
  per route and status (requests/s, 4xx, 5xx, error rate total and per route, latency p50/p95/p99, p95 per route,
  heatmap); saturation from kube-state-metrics and cAdvisor (replicas, restarts, CPU/memory per pod vs requests and
  limits, CPU throttling) and from the Go runtime instrumentation (profile-service now exports it); DB and pgx pool.
  Every query checked against Prometheus; loaded by the sidecar (provisioned, General folder).
- Not covered: 401/403 rejected by Envoy (no Envoy PodMonitor yet), container logs.
- Per-pod series: `service-lib` 0.3.0 sets `OTEL_RESOURCE_ATTRIBUTES` (`service.instance.id` and `k8s.pod.name` = pod
  name via the downward API, `k8s.namespace.name`), which becomes the Prometheus `instance` label. Before, replicas
  wrote into one series and counters looked like constant resets. Checked with 2 replicas: 100 requests through the
  Service counted 54 + 46 per instance, no resets.
- Open: a new series' first sample already contains its requests (the `prometheusremotewrite` exporter drops the
  OTel start time), so `increase()`/`rate()` miss the requests before the first export of every new pod and every new
  route/status combination (a route's first 5xx is not seen). Fix: send OTLP to Prometheus' native OTLP receiver
  with created-timestamp zero ingestion instead of remote write (step 6 change; verify the flags for Prometheus v3.16).
