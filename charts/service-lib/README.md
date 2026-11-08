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
`probes.{liveness,readiness}`, `env` (map), `envFromSecret`, `resources`,
`route.{enabled,host,pathPrefix}`, `auth.{enabled,issuer,jwksUri,jwksBackend,audiences}`.
The Helm release name is the service name (Deployment, Service, HTTPRoute, SecurityPolicy).
