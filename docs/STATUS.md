# Local environment status

Update this file as steps are completed. Steps 0-7 were run and verified on the local cluster (notes below);
step 8 (`make up`/`reset`) is not.

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
  resolve on the docker network `kind` (since renamed to `distro`, see below; step 7's profile-service reaches
  `postgres` on it).
- Fixed: `postgres-init/01-databases.sh` failed on `CREATE ROLE order` (reserved word); identifiers are now quoted.
- Follow-up: the Kafka healthcheck uses `kafka-broker-api-versions.sh`, deprecated in 4.4 in favour of
  `kafka-cluster.sh api-versions`. It still works.

## Docker network rename (2026-11-08)
- The project now uses its own docker network `distro` instead of `kind` (compose services, `DOCKER_NET` in the
  Makefile, exported to kind as `KIND_EXPERIMENTAL_DOCKER_NETWORK`). Step 1 was verified on the old `kind` network;
  rerun its checks (with `--network distro`) after the next `make infra-up`.

## Step 2 notes (2026-11-08)
- Host ports changed from 80/443 to 8080/8443 (`kind/kind.yaml`, `make doctor`, docs). Local URLs and the ZITADEL
  issuer now need `:8080`.
- `make cluster-up` with kind v0.31.0 (node image `kindest/node:v1.35.0`, kind's default; now pinned by digest in
  `kind.yaml`, see "Image pins").
  kind printed the expected `KIND_EXPERIMENTAL_DOCKER_NETWORK` warning and put `distro-control-plane` on the `distro`
  network next to the four stores.
- Node Ready, all kube-system and local-path-storage pods Running. Ports: `127.0.0.1:8080->30080`, `127.0.0.1:8443->30443`.
- A pod reached `postgres:5432`, `redis:6379`, `mongo:27017` and `kafka:9092` by name.

## Step 3 notes (2026-11-08)
- `make edge-up`: release `eg` deployed (`gateway-helm-v1.9.3`, app v1.9.3), 18 Gateway API / Envoy Gateway CRDs.
  GatewayClass `eg` Accepted, Gateway `edge/public` Programmed.
- Envoy Proxy image (Envoy Gateway default): `envoyproxy/envoy:distroless-v1.39.5`; now pinned, see "Image pins".
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
- (2026-11-16) The Go baseline for every service repository is now 1.27.4 (`docs/workflow.md`, "Service conventions").
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
- Not covered: container logs. Requests rejected by Envoy are on the Gateway dashboard (see "Envoy gateway metrics").
- Per-pod series: `service-lib` 0.3.0 sets `OTEL_RESOURCE_ATTRIBUTES` (`service.instance.id` and `k8s.pod.name` = pod
  name via the downward API, `k8s.namespace.name`), which becomes the Prometheus `instance` label. Before, replicas
  wrote into one series and counters looked like constant resets. Checked with 2 replicas: 100 requests through the
  Service counted 54 + 46 per instance, no resets.
- First requests of a new series: with remote write a new series' first sample already contained its requests, so
  `increase()`/`rate()` missed them (every new pod and route/status; a route's first 5xx was invisible). Metrics now go
  collector → Prometheus OTLP receiver (`enableOTLPReceiver`, translation `UnderscoreEscapingWithSuffixes`, so names
  are unchanged) with `created-timestamp-zero-ingestion`, which writes a 0 sample at each point's start time
  (OTLP support checked in the v3.16.0 source; the docs list only scrape protocols). `service-lib` 0.5.0 sets
  `OTEL_GO_X_PER_SERIES_START_TIMESTAMPS=true` (Go SDK v1.47, experimental) so a series starts at its first
  measurement, not at process start. Checked: new 200 and 405 series on a running pod, 30 and 7 requests →
  `increase([2m])` 35 and 8.2 (extrapolated; 0 before), raw samples start with 0. Remote-write receiver disabled (re-enabled later only for Tempo's
  metrics generator, see "Tempo service graph").
  OTLP series no longer carry `otel_scope_*` labels.

## Image pins (2026-11-14)
- `kind/kind.yaml`: `kindest/node:v1.35.0@sha256:452d707d…`, the digest in the kind v0.31.0 release notes and the one
  the running node uses. The `v1.35.0` tag itself already points to another digest (re-pushed), so the digest matters.
- `k8s/envoy-gateway.yaml`: EnvoyProxy `envoyDeployment.container.image`
  `envoyproxy/envoy:distroless-v1.39.5@sha256:9d84a586…`, exactly what Envoy Gateway v1.9.3 deployed; applying it did not
  roll the Envoy Deployment. Both have linux/arm64 builds (`docker manifest inspect`).
- The kind pin takes effect on the next `make cluster-up`; not exercised by recreating the cluster.

## lib-test host (2026-11-14)
- `k8s/dev/lib-test` moved from `api.localtest.me` `/` to its own host `libtest.localtest.me`: on the shared host it
  caught every path the services do not route (with auth). Checked with libtest installed: `libtest.localtest.me/` →
  401 (its policy), `api.localtest.me/` and `/foo` → 404 from Envoy, `/v1/users/me` → 401 (profile); both routes Accepted.
  Runbook: `helm dependency update` instead of `build` for lib-test.

## Security context (2026-11-14)
- `service-lib` 0.5.0: pod `runAsNonRoot: true` and `seccompProfile: RuntimeDefault`; container
  `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `capabilities.drop: [ALL]`. `podSecurityContext`
  and `securityContext` values are merged over the defaults (lists replaced). No writable volume (none needed yet).
- Checks: `helm template` (defaults, pod override, container override), server-side dry run; lib-test (whoami as
  65532, which binds port 80 without capabilities: containerd allows unprivileged ports in pods) and profile
  (distroless nonroot) Running; `/readyz` 200, `/v1/users/me` 200; through Envoy 401 without a token. A server-side
  dry run of the label `pod-security.kubernetes.io/enforce=restricted` on `apps` reports no violations (not enforced).

## X-User-ID on public routes (2026-11-14)
- Found: with `auth.enabled: false` nothing touched `X-User-ID`; lib-test on the old chart passed `X-User-ID: hacker`
  through to the backend. `service-lib` 0.5.0 adds a RequestHeaderModifier `remove: [x-user-id]` to the HTTPRoute when
  auth is off. Checked through Envoy: the header no longer arrives (also when sent twice with different case).
- Not removed when auth is on: Envoy Gateway renders the filter as route `request_headers_to_remove`, which the router
  applies after `jwt_authn`. Tested with a throwaway route and a SecurityPolicy with an inline JWKS (own key and
  token): without the filter the backend gets the token `sub` and a forged value is overwritten; with it the header is
  gone entirely. Test resources deleted.

## Logs in Loki and data source links (2026-11-15)
- profile-service exports its logs over OTLP (its commit `b4d57c7`, deployed): in Loki the index labels are
  `service_name`, `service_instance_id`, `k8s_pod_name`, `k8s_namespace_name`; `trace_id`, `span_id` and the slog
  attributes are structured metadata; the line is the message.
- Grafana data sources: fixed UIDs `prometheus` (kps `grafana.sidecar.datasources.uid`, pinned), `tempo`, `loki`.
  Tempo: `tracesToLogsV2` → Loki with a custom query `{${__tags}} | trace_id="${__span.traceId}"` (tag
  `service.name` → `service_name`, ±1m), `tracesToMetrics` → Prometheus (request rate, p95; `service.name` → `job`),
  `serviceMap` → Prometheus, node graph on. Loki: derived field `trace_id` (matcherType label) → Tempo. Field names
  checked in the Grafana v13.3.0 source; Grafana's built-in Loki trace-to-logs query depends on a feature flag, hence the
  custom query. `$$` escapes in the values (Grafana expands `${...}` in provisioning); the live data sources show `${...}`.
- Checked with a real request through Envoy (token, 404 profile_not_found): trace `e0d345e8…` has Envoy `ingress` and
  router, profile `GET /v1/users/me`, `pool.acquire`, `SELECT`. The trace-to-logs query returns its one log line
  (span_id = profile's server span); that line's `trace_id` arrives as structured metadata (label type S) and looks up
  the same trace (5 spans). Trace-to-metrics queries return data. Not checked by clicking in the browser.
- Service Graph: configured here; enabled on 2026-11-16, see "Tempo service graph".

## Tempo service graph (2026-11-16)
- Tempo's metrics generator is on with the `service-graphs` processor only (`tempo.metricsGenerator`,
  `tempo.overrides.defaults.metrics_generator.processors`; chart 3.2.1 keys checked with `helm show values` and
  `helm template`). WAL in `/var/tempo/generator/wal` (PVC). It writes `traces_service_graph_*` over remote write, so
  Prometheus' remote-write receiver is back on (`enableRemoteWriteReceiver`), used only by Tempo; the collector stays
  on OTLP. Span metrics stay off: they would duplicate the services' SDK RED metrics.
- `pool.acquire` is emitted as a CLIENT span by otelpgx (v0.13.0, kind hardcoded), so it would double the database
  edge and mix pool waits into its latency; the generator excludes it (`filter_policies`, intrinsic `name`). Done for
  profile-service (its `ebab05e`: `otelpgx.WithDisableAcquireTracer()`, deployed; traces have no `pool.acquire`). The
  filter stays as a guard for services that forget the option (required in `docs/workflow.md`).
- Checked through Envoy: 10 requests without a token (401 at Envoy) and 20 with a token (404 profile_not_found).
  Edges (`traces_service_graph_request_total`, plus `_failed_total` and the client/server seconds histograms):
  `client="user", server="public.edge", connection_type="virtual_node"` 20;
  `client="public.edge", server="profile"` (no connection_type) 20, all 20 also in `_failed_total`;
  `client="profile", server="postgres", connection_type="database"` 21 (20 queries plus one statement prepare on a new
  connection; about 41 without the filter). The database node name comes from `server.address`.
- Failed edges: Tempo marks an edge failed if either span is Error. Envoy's router span is a CLIENT span and is Error
  for the 404 (OTel semconv: 4xx is an error on the client side), so the graph's error rate for Envoy → service
  includes 4xx; the dashboards' 5xx panels use the SDK metrics.
- New series start with a 0 sample at the end of the previous minute, so `increase()` counts first requests. The series
  created in the first collection after the Tempo restart lost its 0 (remote write logged `error tailing WAL` at
  startup); later series had it.
- Grafana Explore → Tempo → Service Graph not checked by clicking in the browser; its per-span RED table needs span
  metrics and stays empty.

## service-lib tags, shared workflow, Envoy gateway metrics (2026-11-16)
- service-lib releases get an annotated tag `service-lib-vX.Y.Z` on the commit that changes `Chart.yaml` (rule in
  `CLAUDE.md` and the chart README). `service-lib-v0.5.0` is on `b70793e`; not pushed yet.
- The feature workflow moved from profile-service's `CLAUDE.md` to `docs/workflow.md`, shared by every service
  repository, with the service conventions (Go 1.27.4 baseline) and what each service must provide.
- Envoy gateway metrics: PodMonitor `envoy-gateway-system/envoy-proxy` (pods `app.kubernetes.io/component=proxy`,
  `app.kubernetes.io/managed-by=envoy-gateway`; container port `metrics` 19001, `/stats/prometheus`; every 15 s). Chosen
  over Envoy Gateway's OTLP metrics sink: the endpoint already exists, its names were checked on the real output, and
  it needs no change to Envoy or the collector. A keep-list drops all but the dashboard's metrics (about 280 series
  instead of about 470 families); names are as Envoy exposes them, without `_total`.
- Metrics, per listener (`envoy_http_conn_manager_prefix`, `http-10080` for the public listener; `admin`,
  `eg-ready-http`, `eg-stats-http` and `async-client` are internal): `envoy_http_downstream_rq_xx`
  (`envoy_response_code_class`), `envoy_http_downstream_rq_time_*` (milliseconds), `envoy_http_jwt_authn_denied`
  (401 and 403), `_allowed` (also counts requests whose route needs no token, including unrouted ones), `_jwks_fetch_failed`,
  `envoy_http_no_route` (404 for an unknown path or host). Per route rule (`envoy_cluster_name` =
  `httproute/<ns>/<route>/rule/<n>`): `envoy_cluster_upstream_rq_xx`, `envoy_cluster_upstream_rq_time_*`, only for
  requests forwarded to a backend.
- Limit: Envoy counts JWT denials, unrouted requests and status classes per listener, and every host shares the one
  listener, so rejections are not split by route or host; the class is known, the exact code (401 vs 403) is not.
  Tempo's `public.edge` spans carry host and status if that is ever needed.
- First requests: the listener counters (all five classes, `jwt_authn_*`, `no_route`) exist at 0 from the start, so
  `rate()` counts every request. The per-route-rule class counters are created on first use (profile's cluster has no
  class 5 series yet), and a text scrape carries no created timestamp, so the first response of a new class on a route
  rule is not counted there; the listener panels still count it.
- Gateway dashboard (`dashboards/gateway.json`, uid `gateway`, 13 panels): requests/s, 4xx/5xx share, share rejected at
  the gateway, p95; responses by status class; JWT denied and no-route per second; p50/p95/p99; JWT checks and JWKS
  fetch failures; per route rule upstream responses by class and p95. Every query checked against Prometheus.
- Checked through Envoy: 10 requests without a token and 15 unrouted (10 unknown paths, 5 unknown host) →
  `jwt_authn_denied` +10, `no_route` +15, class 4 +25, all requests +25. Gateway p95 for these local replies 0.5 ms.
  Not checked by clicking in the browser.
