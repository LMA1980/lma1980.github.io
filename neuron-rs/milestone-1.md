# Milestone - 1

A minimal distributed compute unit: the idea is to be able to support links to resources. No transport involved at this level.

## Features:

- Core
  - Neurogenesis (Life cycle of a neuron within a distributed system)
  - Synapses (Linkables)
    - Configuration Backends
    - Logging Backend
    - Metric Backend
    - Tracing Backend
- Configuration Backend
  - Environment variables
    - `<PREFIX>_<KEY_NAME> = <VALUE>`
  - Environment (.env) file
    - See environment variables above for naming convention
  - `<executable name>.toml`
  - `.config\<executable name>\links.toml`
- Observability (trifacta)
  - Logging
  - Metric
  - Tracing
 
## Core

```{r, child='/neuron-rs/overview_diagram.mmd'}
```

### Neurogenesis

The neurogenesis is the lifecycle of a typical neuron. This lifecycle guaranty interoperability with a neuron-runner.

As a side-effect, it will also provide a generic metadata layer to enable traceability.

### Synapses (Linkables)

A Synapses (linkable) are external services definition and public interfaces, helpers, etc. Those can be local operating systems specifics: syslog, logrotation comes to minds. Or most likely be distributed systems: BookKeeper, Zookeeper, Etcd, Consul, Postgres, etc. It can also be other neurons specialized to handle other parts of the workflow.

The idea is to provide a framework to provide an entry point to define adapters that link to the infrastructures.

This is the main feature of a neuron.
