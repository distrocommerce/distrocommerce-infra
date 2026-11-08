# Local environment status

Update this file as steps are completed. Everything below was designed in a chat session and **not yet
run end to end**; configs for steps 1-7 are drafts to verify (chart value keys especially).

| Step | What | Status |
|---|---|---|
| 0 | Tools, Docker Desktop resources, repo skeleton | done |
| 1 | docker-compose stores | done (2026-11-08) |
| 2 | kind cluster with extraPortMappings | done (2026-11-08) |
| 3 | Envoy Gateway v1.9.3 + Gateway | done (2026-11-08) |
| 4 | ZITADEL + its PostgreSQL | not verified |
| 5 | JWT SecurityPolicy | not verified |
| 6 | Observability stack | not verified |
| 7 | Library chart and first service deployment | not verified |
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
