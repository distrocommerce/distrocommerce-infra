# Deployment diagram: Staging and Production (EKS + AWS managed services)

```mermaid
flowchart TB
  client["Client: browser / mobile"] --> nlb["L4 load balancer<br/>NLB, TCP passthrough"]
  nlb --> envoy
  subgraph eks["Kubernetes (EKS)"]
    subgraph edge["ns: edge"]
      certm["cert-manager"]
      gwapi["Gateway API"]
      envoy["Envoy Gateway<br/>JWT, rate limit"]
    end
    subgraph auth["ns: auth"]
      zitadel["ZITADEL<br/>OIDC, PKCE"]
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
  subgraph aws["AWS managed"]
    rds[("PostgreSQL<br/>RDS, services")]
    rdsz[("PostgreSQL<br/>RDS, ZITADEL")]
    ec[("Redis<br/>ElastiCache")]
    mongo[("MongoDB<br/>Atlas or DocumentDB")]
    msk[["Kafka<br/>Amazon MSK"]]
    s3[("Amazon S3<br/>Tempo, Loki data")]
  end
  apps --> rds
  apps --> ec
  apps --> mongo
  apps --> msk
  zitadel --> rdsz
  tempo --> s3
  loki --> s3
```

- Staging and production share this layout; staging uses the smallest instance sizes.
- The observability stack runs in the same cluster; Tempo and Loki keep their data in S3.
- Databases, cache, Kafka and S3 are AWS managed services outside the cluster.
