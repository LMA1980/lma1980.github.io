# `action-runner` Architecture & Crate Reference

**Crate**: `action-runner`\
**Version**: `0.2.0` (Edition 2021)\
**Role**: Lightweight, bare-metal CI execution sidecar agent engineered for SpacemiT Key Stone K3 hardware\
**Repository**: [`LMA1980/ActionRunner-rs`](https://github.com/LMA1980/ActionRunner-rs)\
**Rustdoc Reference**: [`action_runner` API Reference](../../api/action_runner/index.html)

______________________________________________________________________

## 1. Purpose & System Context

`action-runner` is a lightweight, zero-copy CI worker agent designed to run natively on bare-metal RISC-V SBCs (such as SpacemiT K3 boards).

Standard cloud CI agents (such as GitHub Actions runner) are heavy, rely on container engines (Docker/containerd) that add massive overhead on edge RISC-V hardware, and lack awareness of heterogeneous CPU clusters or hardware micro-benchmarks. `action-runner` provides:

- Direct bare-metal process execution under dedicated service account isolation (`action-runner`).
- Exclusive target-node stage locking (`US-25` / Issue #82): drains active shared tasks before running hardware benchmarks and locks the entire node to eliminate noise.
- Live streaming of stdout/stderr and metrics over zero-copy IPC (`action-runner-ipc`).
- Process group isolation and watchdog termination for runaway or wedged commands.

______________________________________________________________________

## 2. Key Public Types & Components

### 2.1 `WorkerAgent`

The primary daemon client connecting to the central controller:

```rust
pub struct WorkerAgent {
    config: WorkerConfig,
    active_stages: Arc<Mutex<HashMap<StageId, StageExecutionHandle>>>,
    exclusive_lock: Arc<AtomicBool>,
}
```

### 2.2 `StageRunner`

Spawns pipeline tasks using asynchronous process supervisors:

- Captures stdout/stderr via non-blocking pipes.
- Enforces per-stage execution timeouts (`timeout_seconds`).
- Streams Apache Arrow record batches of log lines and resource metrics directly to `action-runner-controller`.
- Orchestrates distributed `sccache` compilation caching per stage and per step:
  - `StageRunner::resolve_effective_sccache_mode`: Resolves the stage-level pre-flight requirement across eligible Rust compilation steps (`cargo-check`, `cargo-test`, `cargo-clippy`, `cargo-build`, `cargo-nextest`, `cargo-bench`, `cargo-doc`), returning `SccacheMode::Mandatory` if any eligible step is `Mandatory`, `SccacheMode::Try` if any eligible step is `Try`, or `SccacheMode::Disabled`.
  - `StageRunner::ensure_sccache_server_healthy`: Runs a 5-second bounded `sccache --show-stats` check prior to stage execution, automatically restarting the local `sccache` daemon if it was hijacked into `Local disk` mode while `SCCACHE_BUCKET` is configured in `/etc/action-runner/sccache.env` or if its local socket is wedged.
  - `StageRunner::compute_sccache_env`: Injects `RUSTC_WRAPPER=sccache`, `CARGO_INCREMENTAL=0`, `SCCACHE_IDLE_TIMEOUT=0` (anti-race default), and `/etc/action-runner/sccache.env` variables strictly into eligible Rust compilation commands while excluding `cargo-llvm-cov`, `cargo-audit`, `cargo-fmt`, and `cargo-miri`.
  - `StageRunner::capture_sccache_stats` & `SccacheStatsDelta::saturating_delta`: Snapshots `sccache --show-stats` before and after stage execution and attaches the monotonic `SccacheStatsDelta` to `StageCompletionReport`.

### 2.3 `WorkerConfig`

Defines agent operational parameters:

- `worker_id`: Unique identifier for the SBC node.
- `controller_url`: WebSocket URL of the controller daemon.
- `max_concurrent_slots`: Enforced at `1` (`max_slots = 1`) while bounding per-stage parallelism via thread budget environment variables (`CARGO_BUILD_JOBS`, `RAYON_NUM_THREADS`, `RUST_TEST_THREADS`).
- `workspace_root`: Base working directory for repository checkouts.
- `sccache_env_file`: Optional path to `/etc/action-runner/sccache.env` (`WorkerConfig::load_sccache_env()` parses `KEY=VALUE` pairs and strips `RUSTC_WRAPPER` and `CARGO_BUILD_RUSTC_WRAPPER` so wrapper injection cannot be forced onto non-compilation tools).

______________________________________________________________________

## 3. Exclusive Stage Isolation (US-25)

Hardware micro-benchmarks (e.g. measuring RVV 1.0 throughput or A100 matrix jitter) require 100% of the SoC resources with zero background interference:

1. When a task arrives with `exclusive: true`, `WorkerAgent` verifies no other slots are active.
1. It acquires all execution permits, blocking any concurrent jobs.
1. The benchmark executes with exclusive access to CPU clusters, caches, and memory buses.
1. On completion, timeout, or cancellation, the exclusive permit is deterministically released, restoring normal scheduling.

______________________________________________________________________

## 4. Operator `sccache` Integration Guide

Enable `sccache` on any `action-runner` worker node by configuring the binary and environment file:

1. **Install `sccache` Binary**: Place `sccache` in `/usr/local/bin/sccache` (`0755`). On startup, `action-runner` checks `which sccache` and automatically advertises `"sccache"` in `NodeCapabilities.supported_tools`.
1. **Create `/etc/action-runner/sccache.env` (`0600`, `action-runner:action-runner`)**:
   ```ini
   SCCACHE_BUCKET=ci-sccache
   SCCACHE_ENDPOINT=http://192.0.2.10:3900
   SCCACHE_REGION=garage
   SCCACHE_S3_USE_SSL=false
   SCCACHE_S3_KEY_PREFIX=actionrunner-v1/
   AWS_ACCESS_KEY_ID=GKxxxxxxxxxxxxxxxxxxxxxxxx
   AWS_SECRET_ACCESS_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   SCCACHE_SERVER_PORT=4226
   SCCACHE_IDLE_TIMEOUT=0
   ```
1. **Verify `MuIsolation` Landlock Grants**: Ensure `.actionrunner/security.yml` and `/etc/mu-isolation/ceiling.yml` grant `/usr/local/bin` and `/usr/bin` in `read_paths` and `exec_paths`.
1. **Verify Under Service Account**:
   ```bash
   sudo -u action-runner sh -a -c '. /etc/action-runner/sccache.env && sccache --stop-server >/dev/null 2>&1 || true && sccache --start-server && sccache --show-stats'
   sudo systemctl restart action-runner
   ```

______________________________________________________________________

## 5. Hardware & Platform Invariants

1. **Bare-Metal Sandboxing**: Runs under isolated system user `action-runner` with `ProtectHome=read-only`.
1. **Git-Only Synchronization**: Always synchronizes code via Git; avoids non-atomic file sync (`rsync`).
1. **Target Toolchain Verification**: Directly integrates with native RISC-V Rust toolchains (`/var/lib/action-runner/.rustup`) and GFM table formatters.

______________________________________________________________________

## 6. Inter-Crate Dependencies

- **Imports**: `action-runner-ipc`, `tokio`, `tokio-tungstenite`, `arrow`, `thiserror`, `serde`
- **Consumers**: `action-runner-controller`
