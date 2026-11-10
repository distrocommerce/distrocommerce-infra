# DistroCommerce local environment. Draft: not yet run end to end, verify each target.
# Order matters: infra-up creates the docker network "$(DOCKER_NET)" before the cluster is created.

# Own docker network so other kind-based projects do not share it (or hostnames like postgres).
DOCKER_NET := distro
export KIND_EXPERIMENTAL_DOCKER_NETWORK := $(DOCKER_NET)

COMPOSE = docker compose -f compose/compose.yaml --env-file compose/.env

EG_VERSION            ?= v1.9.3
ZITADEL_CHART_VERSION ?= 10.5.0
# Observability charts come from OCI registries on ghcr.io (GitHub Pages repo indexes are large and can be slow).
KPS_VERSION           ?= 93.1.1
TEMPO_VERSION         ?= 3.2.1
LOKI_VERSION          ?= 21.1.1
OTEL_VERSION          ?= 0.178.2

.PHONY: doctor up reset infra-up infra-down infra-reset cluster-up cluster-down edge-up auth-up obs-up db-secrets

doctor: ## run before the cluster exists (ports 8080/8443 must be free)
	@for t in docker kind kubectl helm make jq psql; do \
	  command -v $$t >/dev/null || { echo "MISSING: $$t"; exit 1; }; \
	done
	@docker compose version >/dev/null || { echo "MISSING: docker compose v2"; exit 1; }
	@! lsof -nP -iTCP:8080 -sTCP:LISTEN >/dev/null 2>&1 || { echo "port 8080 busy"; exit 1; }
	@! lsof -nP -iTCP:8443 -sTCP:LISTEN >/dev/null 2>&1 || { echo "port 8443 busy"; exit 1; }
	@echo "tools ok"

up: infra-up cluster-up edge-up auth-up obs-up db-secrets

reset: cluster-down infra-reset

infra-up:
	@docker network inspect $(DOCKER_NET) >/dev/null 2>&1 || docker network create $(DOCKER_NET)
	$(COMPOSE) up -d --wait

infra-down:
	$(COMPOSE) down

infra-reset:
	$(COMPOSE) down -v

cluster-up:
	kind create cluster --config kind/kind.yaml

cluster-down:
	kind delete cluster --name distro

edge-up:
	kubectl create namespace edge --dry-run=client -o yaml | kubectl apply -f -
	kubectl create namespace apps --dry-run=client -o yaml | kubectl apply -f -
	helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
	  --version $(EG_VERSION) -n envoy-gateway-system --create-namespace \
	  -f k8s/envoy-gateway-values.yaml
	kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available
	kubectl apply -f k8s/envoy-gateway.yaml

auth-up:
	@test -n "$(ZITADEL_CHART_VERSION)" || { echo "set ZITADEL_CHART_VERSION"; exit 1; }
	kubectl create namespace auth --dry-run=client -o yaml | kubectl apply -f -
	kubectl -n auth get secret zitadel-masterkey >/dev/null 2>&1 || \
	  kubectl -n auth create secret generic zitadel-masterkey \
	    --from-literal=masterkey="$$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
	kubectl -n auth get secret zitadel-postgres >/dev/null 2>&1 || \
	  kubectl -n auth create secret generic zitadel-postgres \
	    --from-literal=admin-password=zitadel_admin_dev \
	    --from-literal=user-password=zitadel_user_dev
	kubectl apply -f k8s/zitadel/postgres.yaml
	kubectl -n auth rollout status statefulset/zitadel-postgres
	helm repo add zitadel https://charts.zitadel.com
	helm upgrade --install zitadel zitadel/zitadel --version $(ZITADEL_CHART_VERSION) \
	  -n auth -f k8s/zitadel/values.yaml --wait --timeout 10m
	kubectl apply -f k8s/zitadel/httproute.yaml
	kubectl apply -f k8s/zitadel/jwks-backend.yaml

obs-up:
	@for v in "$(KPS_VERSION)" "$(TEMPO_VERSION)" "$(LOKI_VERSION)" "$(OTEL_VERSION)"; do \
	  test -n "$$v" || { echo "set KPS_VERSION, TEMPO_VERSION, LOKI_VERSION and OTEL_VERSION"; exit 1; }; \
	done
	kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
	helm upgrade --install kps oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack \
	  --version $(KPS_VERSION) -n observability -f k8s/observability/kps-values.yaml --wait --timeout 10m
	helm upgrade --install tempo oci://ghcr.io/grafana-community/helm-charts/tempo \
	  --version $(TEMPO_VERSION) -n observability -f k8s/observability/tempo-values.yaml --wait
	helm upgrade --install loki oci://ghcr.io/grafana-community/helm-charts/loki \
	  --version $(LOKI_VERSION) -n observability -f k8s/observability/loki-values.yaml --wait --timeout 10m
	helm upgrade --install otel-collector oci://ghcr.io/open-telemetry/opentelemetry-helm-charts/opentelemetry-collector \
	  --version $(OTEL_VERSION) -n observability -f k8s/observability/otel-values.yaml --wait
	kubectl apply -f k8s/observability/grafana-route.yaml

# Per-service DB secrets (add a block per service).
db-secrets:
	kubectl create namespace apps --dry-run=client -o yaml | kubectl apply -f -
	kubectl -n apps create secret generic profile-db \
	  --from-literal=DATABASE_URL='postgres://profile:profile_dev@postgres:5432/profile?sslmode=disable' \
	  --dry-run=client -o yaml | kubectl apply -f -
