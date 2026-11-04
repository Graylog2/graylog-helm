# MongoDB topology and scaling

```sh
# scaling out: add more MongoDB nodes to your replica set
helm upgrade graylog graylog/graylog -n graylog --set mongodb.replicas=4 --reuse-values
```

## MongoDB topology

By default, the chart deploys MongoDB with a **production-recommended topology**: 3 data-bearing replicas with no arbiters. This configuration:
- Supports `w:majority` writes even with one replica down
- Handles rolling upgrades and maintenance gracefully
- Provides true high availability without cost overhead

**Example: Default production topology**
```yaml
mongodb:
  replicas: 3
  arbiters: 0
```

For **cost-optimized test/staging environments**, you may use the Primary-Secondary-Arbiter (PSA) topology instead. However, be aware that this topology is not recommended by MongoDB for production use:

```yaml
mongodb:
  replicas: 2
  arbiters: 1
```

> [!WARNING]
> With PSA topology, if one data-bearing replica fails, `w:majority` writes will stall until the member recovers.
