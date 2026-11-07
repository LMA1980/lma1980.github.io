# `action-runner-controller` Architecture & Crate Reference

**Crate**: `action-runner-controller`\
**Version**: `0.1.0` (Edition 2021)\
**Role**: GitHub Webhook ingress controller, DAG stage scheduler, DuckDB metrics aggregator, and dynamic SVG quality scorecard generator\
**Repository**: [`LMA1980/ActionRunner-controller`](https://github.com/LMA1980/ActionRunner-controller)\
**Rustdoc Reference**: [`action_runner_controller` API Reference](../../api/action_runner_controller/index.html)

______________________________________________________________________

## 1. Purpose & System Context

`action-runner-controller` is the coordination hub of the ActionRunner CI platform. It receives GitHub events, parses YAML workflow definitions (`.actionrunner/*.yml`), orchestrates DAG execution across distributed bare-metal workers, records telemetry in DuckDB, and generates real-time SVG status scorecards.

______________________________________________________________________

## 2. Key Public Types & Components

### 2.1 `WebhookRouter`

Authenticates incoming GitHub webhooks:

- Verifies `X-Hub-Signature-256` using HMAC-SHA256. Secret paths fail closed if unreadable.
- Event Coalescing: Coalesces rapid sequential push events on the same branch to prevent CI build storms.

### 2.2 `DagScheduler` & `ClusterRegistry`

Manages distributed workers and pipeline execution:

- Parses stage dependencies (`depends_on: [lint, build]`).
- Leases worker slots based on capacity (`lease_slot`).
- Enforces **Drain-Before-Dispatch** for exclusive stages (`exclusive: true`): holds exclusive stages in `Pending` until target node slots drain to 0, then reserves all slots until stage completion.
- Enforces **Capability-Aware `sccache` Scheduling** (`ActionRunnerWorkflow::effective_stage_tags`):
  - Evaluates whether any `sccache`-eligible Rust compilation tool in a stage (`cargo-check`, `cargo-test`, `cargo-clippy`, `cargo-build`, `cargo-nextest`, `cargo-bench`, `cargo-doc`) resolves to `SccacheMode::Mandatory` (`task.sccache.unwrap_or(workflow.sccache)`).
  - Automatically appends `"sccache"` to the stage's required capability tags when `Mandatory`, ensuring `lease_slot` only dispatches the stage to workers advertising `"sccache"` in `NodeCapabilities.supported_tools`.
  - Stages with `SccacheMode::Try` retain their original stage tags so they schedule onto any matching worker and gracefully fall back if `sccache` is absent.

### 2.3 `DuckDbStore`

Records build outcomes, test durations, coverage percentages (`cargo llvm-cov`), clippy warnings, `sccache` hit/miss/compile telemetry (`SccacheStatsDelta`), and micro-benchmark latencies in native DuckDB tables:

- Parameterized SQL statements eliminate SQL injection risks.
- Provides historical rollups for project status badges.

### 2.4 `SvgBadgeGenerator`

Generates live, dynamic SVG badges displaying:

- Pipeline build status (Passing / Failing).
- Code coverage percentage.
- Quality scorecards and `sccache` compilation cache hit-rate percentages (`hit_rate_pct()`) with `hits/total` counters.

______________________________________________________________________

## 3. Network Endpoints

- `POST /webhook`: GitHub webhook delivery ingress.
- `GET /ws/worker`: WebSocket connection point for `action-runner` agents.
- `GET /ws/telemetry`: WebSocket streaming telemetry for `action-runner-web` dashboard.
- `GET /api/jobs`: List active and completed jobs.
- `GET /badges/:repo/:branch.svg`: Dynamic SVG scorecard badge.

______________________________________________________________________

## 4. Inter-Crate Dependencies

- **Imports**: `action-runner-ipc`, `duckdb`, `axum`, `tokio`, `serde`, `hmac`, `sha2`, `arrow`
- **Consumers**: `action-runner-web`, GitHub webhooks
