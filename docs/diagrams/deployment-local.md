# Deployment diagram: Local (kind + docker-compose)

```mermaid
flowchart TB
  client["Client: browser / mobile"] --> envoy
  subgraph kind["kind"]
    subgraph edge["ns: edge"]
      gwapi["Gateway API<br/>HTTPRoute, SecurityPolicy"] --> envoy["Envoy Gateway<br/>JWT, rate limit, CORS"]
    end
    subgraph auth["ns: auth"]
      zitadel["ZITADEL<br/>auth.localtest.me"] --> zdb[("PostgreSQL")]
    end
    subgraph apps["ns: apps (gRPC between services)"]
      profile
      product
      order
      payment
      inventory
      notification
    end
    subgraph obs["ns: observability"]
      prom["Prometheus"]
      otel["OTel Collector"]
      grafana["Grafana"]
      tempo["Tempo"]
      loki["Loki"]
      otel --> tempo
      otel --> loki
    end
    envoy --> zitadel
    envoy --> apps
  end
  subgraph compose["docker-compose"]
    pg[("PostgreSQL")]
    redis[("Redis")]
    mongo[("MongoDB")]
    kafka[["Kafka (KRaft)"]]
  end
  apps --> pg
  apps --> redis
  apps --> mongo
  apps --> kafka
```

- kind runs Envoy Gateway, ZITADEL with its own PostgreSQL, the microservices and the whole observability stack.
- docker-compose runs only the stateful stores: PostgreSQL, Redis, MongoDB and Kafka (KRaft).
- All kind-to-compose traffic flows outward from the cluster.
