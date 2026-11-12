# Local environment runbook (macOS, Docker Desktop, kind)

Run everything from the root of this repo. Configs live in `compose/`, `kind/`, `k8s/`, `charts/`.
Do each step, run its checks, then go on. Chart value keys are drafts: compare with `helm show values`.

## Step 0. Tools
- Docker Desktop: Settings → Resources: 8 CPUs, 16 GB RAM, 1-2 GB swap, 60 GB disk (ceilings, not reservations).
- Needed: `docker` (+ compose v2), `kind`, `kubectl`, `helm`, `make`, `jq`, `psql` (`brew install libpq && brew link --force libpq`), `git`.
  Optional: `k9s`. Skipped on purpose: `kcat` (Kafka is checked through the container), `cloud-provider-kind`.
- `kind get clusters` must be empty; ports 8080/8443 and 5432/6379/27017/9094 must be free
  (`sudo lsof -nP -iTCP:8080 -iTCP:8443 -sTCP:LISTEN`). `make doctor` checks tools and 8080/8443; run it before the
  cluster exists (afterwards kind holds 8080/8443).

## Step 1. docker-compose stores
Files: `compose/compose.yaml`, `compose/.env.example` (copy to `compose/.env`), `compose/postgres-init/01-databases.sh`.
1. `docker manifest inspect` the four image tags (all confirmed on 2026-11-08).
2. `make infra-up` (creates the docker network `distro` if missing, then `compose up -d --wait`).
3. Checks:
   - `docker compose -f compose/compose.yaml --env-file compose/.env ps`: four services `healthy`.
   - `PGPASSWORD=profile_dev psql -h localhost -U profile -d profile -c "select version();"` → PostgreSQL 18.6.
   - redis: `exec redis redis-cli ping` → PONG; mongo: `exec mongo mongosh -u root -p mongo_dev --authenticationDatabase admin --eval "db.runCommand({ping:1})"`.
   - kafka: `exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list`.
   - names resolve on the network: `docker run --rm --network distro busybox:1.36 nslookup postgres` (and `kafka`).
- If mongo previously ran `mongo:8.0` on the same volume: `make infra-reset` first (featureCompatibilityVersion error).

## Step 2. kind cluster
File: `kind/kind.yaml` (single control-plane node, host 8080/8443 → node ports 30080/30443, bound to 127.0.0.1).
1. `make cluster-up`; `kubectl get nodes` (Ready), `kubectl get pods -A`.
2. `docker ps --filter name=distro-control-plane --format '{{.Ports}}'` shows 127.0.0.1:8080->30080 and 8443->30443.
   Host ports are 8080/8443 (not 80/443), so the port is part of every local URL and of the ZITADEL issuer.
3. Pods reach compose stores by name:
   `kubectl run nettest --rm -i --restart=Never --image=busybox:1.36 -- sh -c 'for t in postgres:5432 redis:6379 mongo:27017 kafka:9092; do h=${t%:*}; p=${t#*:}; nc -w 2 $h $p </dev/null && echo "$t open" || echo "$t FAIL"; done'`
4. If kind does not adopt the pre-created `distro` network or names do not resolve: `make infra-down`,
   `docker network rm distro`, `make cluster-up`, `make infra-up`.

## Step 3. Envoy Gateway (v1.9.3)
Files: `k8s/envoy-gateway-values.yaml`, `k8s/envoy-gateway.yaml`, `k8s/dev/echo.yaml`.
1. `make edge-up` (namespaces, helm release `eg` in `envoy-gateway-system`, then GatewayClass/Gateway/EnvoyProxy).
   Create namespaces `auth` and `observability` as well when you reach those steps (the make targets do it).
2. Checks: `helm list -n envoy-gateway-system` (gateway-helm-v1.9.3); `kubectl get crd | grep -E "gateway.networking.k8s.io|gateway.envoyproxy.io"`;
   `kubectl get gatewayclass eg` (Accepted); `kubectl get gateway -n edge public` (Programmed);
   `kubectl get svc -n envoy-gateway-system` (NodePort 80:30080).
3. Test: `kubectl apply -f k8s/dev/echo.yaml`; `curl -i http://echo.localtest.me:8080/` → 200 "hello from envoy"; then delete it.
   Debug: Gateway/HTTPRoute `status.conditions`.

## Step 4. ZITADEL
Files: `k8s/zitadel/{postgres,values,httproute,jwks-backend}.yaml`. `make auth-up` (chart pinned by `ZITADEL_CHART_VERSION`, 10.5.0;
newer ones: `helm repo add zitadel https://charts.zitadel.com && helm search repo zitadel/zitadel --versions`).
- The target creates the masterkey and DB-password secrets if absent (32-char masterkey, never change it), applies the
  ZITADEL Postgres StatefulSet, installs the chart, applies the route and the JWKS Backend.
- Values and Service names (`zitadel:8080` h2c, `zitadel-login:3000`) are checked against chart 10.5.0. After a chart
  bump, compare `helm show values` with `k8s/zitadel/values.yaml` and `kubectl get svc -n auth` with `httproute.yaml`.
- Pods: `zitadel`, `zitadel-login`, `zitadel-postgres-0` Running; jobs `zitadel-init`, `zitadel-setup` Complete.
- Checks: `curl -s http://auth.localtest.me:8080/.well-known/openid-configuration | jq .issuer` → `"http://auth.localtest.me:8080"`;
  console `http://auth.localtest.me:8080/ui/console`, admin `admin@distrocommerce.auth.localtest.me` / `Password1!` (login name shown in console).
- In the console create: project `distrocommerce`; a service account (Users → Service Accounts, e.g. `local-test`) with
  **access token type JWT**, then Actions → Generate Client Secret. The client ID is the user name.
  IDs change after every `make reset` until the ZITADEL Terraform provider automates this.

## Step 5. JWT on Envoy
Files: `k8s/dev/whoami.yaml`, `k8s/dev/jwt-policy.yaml`, `k8s/zitadel/jwks-backend.yaml`; Backend API is enabled in
`k8s/envoy-gateway-values.yaml` (restart the controller after changing it).
- Token: `curl -s -u "$CLIENT_ID:$CLIENT_SECRET" -d grant_type=client_credentials -d scope="openid urn:zitadel:iam:org:project:id:${PROJECT_ID}:aud" http://auth.localtest.me:8080/oauth/v2/token | jq -r .access_token`
  (starts with `eyJ`; decode: `jq -R 'split(".")[1] | @base64d | fromjson'`).
- Tests against `http://api.localtest.me:8080/`: no token → 401; token → 200 with `X-User-Id` = sub; a client-supplied
  `X-User-ID: hacker` must be overwritten (if not, the trust model is broken: stop); garbage token → 401.
- Tampered signature: change a character in the middle of the signature, not the last one (the last base64url
  character of an RS256 signature carries padding bits, so changing it may leave the signature valid):
  `H=${TOKEN%.*}; S=${TOKEN##*.}; c=${S:100:1}; [ "$c" = A ] && r=B || r=A; BAD="$H.${S:0:100}$r${S:101}"` → 401
  "Jwt verification fails".
- Audience: `kubectl -n apps patch securitypolicy jwt-zitadel --type=json -p '[{"op":"add","path":"/spec/jwt/providers/0/audiences","value":["<project id>"]}]'`
  → token still 200; with a wrong ID → **403** "Audiences in Jwt are not allowed" (Envoy answers 403, not 401).
- Counters: port-forward the Envoy pod's admin port 19000 and read `/stats` (`jwt_authn.allowed|denied|jwks_fetch_*`).
- Failures: `Jwks remote fetch is failed` → Backend not accepted / Backend API disabled; issuer mismatch → compare `iss`.
  One `jwks_fetch_failed` with "cluster ... is not configured" right after applying the policy is a startup race; it
  refetches on its own.
- `Jwt is missing` → no `Authorization` header was sent (for example `$TOKEN` is empty in a new shell).
- Remove the test resources afterwards (keep the `zitadel-jwks` Backend: `make auth-up` manages it).

## Step 6. Observability (`make obs-up`)
Files: `k8s/observability/*`. Charts are pulled as OCI from ghcr.io and pinned in the `Makefile` (`KPS_VERSION` 93.1.1,
`TEMPO_VERSION` 3.2.1 from grafana-community, `LOKI_VERSION` 21.1.1, `OTEL_VERSION` 0.178.2); no `helm repo add` needed.
- Order: kube-prometheus-stack (Prometheus + Grafana, release `kps`) → Tempo → Loki (Monolithic, filesystem) →
  OTel Collector (contrib image) → Grafana route `http://grafana.localtest.me:8080` (admin/admin).
- kps 93.1.1 ships Prometheus Operator v0.95.1, which has no arm64 images: `kps-values.yaml` pins operator and
  config-reloader to v0.95.2. Symptom without it: `kps-operator` in ImagePullBackOff ("no match for platform in manifest").
- Checks: `helm list -n observability` (4 releases deployed); all pods Running; in Grafana the Prometheus, Tempo and Loki
  data sources pass "Save & test" (or `GET /api/datasources/uid/<uid>/health`).
- Test the pipeline: send each signal with telemetrygen (arm64 build: `v0.163.0`):
  `kubectl run tg-traces -n observability --rm -i --restart=Never --image=ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.163.0 -- traces --otlp-endpoint=otel-collector.observability.svc.cluster.local:4317 --otlp-insecure --duration=5s --rate=5 --service=step6-check`
  (repeat with `metrics` and `logs`). Then Grafana → Explore: Tempo `service.name=step6-check`, Loki
  `{service_name="step6-check"}`, Prometheus `gen{job="step6-check"}`.
- Envoy tracing: `telemetry.tracing` in `k8s/envoy-gateway.yaml` (explicit `samplingRate`; no ReferenceGrant needed for
  the cross-namespace collector). Requests through Envoy show up in Tempo as service `public.edge`, root span `ingress`.
- Grafana keeps data sources in its database (emptyDir): after removing one from the values, restart `kps-grafana`.
- Container stdout log shipping is not set up (decide later: Alloy or a filelog DaemonSet).

## Step 7. Deploying a service with the library chart
- Library chart: `charts/service-lib/` (see its README). A service repository has a thin chart (`deploy/chart`) that
  depends on it, plus `values-local.yaml`. The release name is the service name. Auth is on by default and needs
  `auth.issuer` and `auth.audiences` (the ZITADEL project ID, as a quoted string); set `auth.enabled: false` for public
  routes. The chart sets the OTel env vars (service name, collector endpoint).
- Test the library chart without a real service (stand-in `traefik/whoami`):
  `helm dependency build k8s/dev/lib-test`, then
  `helm upgrade --install libtest k8s/dev/lib-test -n apps --set-string 'auth.audiences={<project id>}' --wait`.
  Expect: route and policy Accepted; no token → 401; token → 200 with `X-User-Id` = sub; forged `X-User-ID`
  overwritten; upgrade with a wrong audience → 403. Then `helm uninstall libtest -n apps`.
- Per-service `DATABASE_URL` secret: `make db-secrets` (add one block per service; the host `postgres` resolves through
  the docker network `distro`).
- What the chart expects from a service: it listens on `service.port`, serves the liveness and readiness paths given in
  `probes.*`, and reads its configuration from `env` and the `envFromSecret` secret. Envoy sends the token `sub` in `X-User-ID`.
- Build and deploy loop from a service repository: build an image tagged with the short git SHA,
  `kind load docker-image <image> --name distro`, then
  `helm upgrade --install <service> deploy/chart -n apps -f deploy/chart/values-local.yaml --set image.tag=<tag>`.
- Checks: `kubectl get pods,httproute,securitypolicy -n apps`; 401 without a token and 200 with a valid one;
  the service's trace is visible in Tempo.

## Step 8. Automation
`make up` / `make reset` are drafted in the Makefile (not yet exercised). Optional Tilt (one Tiltfile driving sibling
service repos, web UI) or Skaffold (declarative, per project): they automate build → `kind load` → helm upgrade on file save.
k9s is a handy cluster viewer; `kubectl` skills remain the base.
