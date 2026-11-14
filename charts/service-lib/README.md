# service-lib

Helm library chart. A service repository has a thin chart (`deploy/chart`) that depends on it
(`file://../../../distrocommerce-infra/charts/service-lib` while repos are sibling checkouts;
later an OCI registry) and includes the templates:

```yaml
{{ include "service-lib.deployment" . }}
---
{{ include "service-lib.service" . }}
---
{{ include "service-lib.httproute" . }}
---
{{ include "service-lib.securitypolicy" . }}
```

Values used: `image.{repository,tag,pullPolicy}`, `replicaCount`, `service.port`,
`probes.{liveness,readiness}`, `env` (map), `envFromSecret`, `resources`, `podSecurityContext`, `securityContext`,
`route.{enabled,host,pathPrefix}`, `auth.{enabled,issuer,audiences,jwksUri,jwksBackend,jwksBackendPort}`.
The Helm release name is the service name (Deployment, Service, HTTPRoute, SecurityPolicy).

Auth (SecurityPolicy, rendered when `route.enabled`):
- On unless `auth.enabled: false` (a missing value never leaves a route unprotected). Use `false` only for public routes.
- Required when on: `auth.issuer` (locally `http://auth.localtest.me:8080`) and `auth.audiences` (the ZITADEL project
  ID). Audiences must be strings: quote them in YAML (`audiences: ["<project id>"]`) or use `--set-string`;
  an unquoted 18-digit ID is parsed as a number and can lose precision, so the chart rejects it.
- Defaults: `jwksUri` = `<issuer>/oauth/v2/keys`, `jwksBackend` = `zitadel-jwks` (the Backend from `make auth-up`,
  in namespace `apps`), `jwksBackendPort` = 8080.
- Envoy validates the token and sets `X-User-ID` to its `sub` (a client-supplied value is overwritten). Missing or
  invalid token → 401, wrong audience → 403.
- With `auth.enabled: false` the HTTPRoute removes `X-User-ID` (RequestHeaderModifier), so a client cannot spoof an
  identity on a public route. It is not removed when auth is on: Envoy applies route header changes after the JWT
  filter, so the removal would also delete the `sub` it set.

OpenTelemetry: the Deployment always sets `OTEL_SERVICE_NAME` (release name), `OTEL_EXPORTER_OTLP_ENDPOINT`
(`http://otel-collector.observability.svc.cluster.local:4317`) and `OTEL_RESOURCE_ATTRIBUTES`
(`service.instance.id` and `k8s.pod.name` = pod name, `k8s.namespace.name`); an entry with the same name in `env`
overrides them. `service.instance.id` becomes the Prometheus `instance` label, so each replica has its own series; an
override of `OTEL_RESOURCE_ATTRIBUTES` must keep it (`service.instance.id=$(POD_NAME),...`). `POD_NAME` and
`POD_NAMESPACE` come from the downward API and are reserved. `OTEL_GO_X_PER_SERIES_START_TIMESTAMPS=true` (Go SDK,
experimental) gives each series its own start time, which Prometheus turns into a 0 sample so the first increase of a
new route/status counts.

Security context: secure by default (meets Pod Security "restricted"). Pod: `runAsNonRoot: true`,
`seccompProfile.type: RuntimeDefault`. Container: `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`,
`capabilities.drop: [ALL]`. `podSecurityContext` and `securityContext` (maps) are merged over these defaults, so a
service sets only what differs, e.g. `podSecurityContext.runAsUser: 65532` for an image that runs as root, or
`securityContext.readOnlyRootFilesystem: false`. Lists are replaced, not merged (`capabilities.drop`). The image must
run as a numeric non-root user (distroless `nonroot` does); the root filesystem is read-only and there is no writable
volume, so the service must not write files.

Test chart: `k8s/dev/lib-test` deploys `traefik/whoami` through this chart (see the runbook, step 7).
