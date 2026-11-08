# Local environment status

Update this file as steps are completed. Everything below was designed in a chat session and **not yet
run end to end**; configs for steps 1-7 are drafts to verify (chart value keys especially).

| Step | What | Status |
|---|---|---|
| 0 | Tools, Docker Desktop resources, repo skeleton | done |
| 1 | docker-compose stores | done (2026-11-08) |
| 2 | kind cluster with extraPortMappings | not verified |
| 3 | Envoy Gateway v1.9.3 + Gateway | not verified |
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
