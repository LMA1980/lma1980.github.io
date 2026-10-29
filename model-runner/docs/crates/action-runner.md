# `action-runner` Architecture & Crate Reference

**Crate**: `action-runner`  
**Version**: `0.2.0` (Edition 2021)  
**Role**: Lightweight, bare-metal CI execution sidecar agent engineered for SpacemiT Key Stone K3 hardware  
**Repository**: [`LMA1980/ActionRunner-rs`](https://github.com/LMA1980/ActionRunner-rs)  
**Rustdoc Reference**: [`action_runner` API Reference](../../api/action_runner/index.html)

---

## 1. Purpose & System Context

`action-runner` is a lightweight, zero-copy CI worker agent designed to run natively on bare-metal RISC-V SBCs (such as SpacemiT K3 boards).

Standard cloud CI agents (such as GitHub Actions runner) are heavy, rely on container engines (Docker/containerd) that add massive overhead on edge RISC-V hardware, and lack awareness of heterogeneous CPU clusters or hardware micro-benchmarks. `action-runner` provides:
- Direct bare-metal process execution under dedicated service account isolation (`action-runner`).
- Exclusive target-node stage locking (`US-25` / Issue #82): drains active shared tasks before running hardware benchmarks and locks the entire node to eliminate noise.
- Live streaming of stdout/stderr and metrics over zero-copy IPC (`action-runner-ipc`).
- Process group isolation and watchdog termination for runaway or wedged commands.

---

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

### 2.3 `WorkerConfig`
Defines agent operational parameters:
- `worker_id`: Unique identifier for the SBC node.
- `controller_url`: WebSocket URL of the controller daemon.
- `max_concurrent_slots`: Maximum parallel shared tasks (typically 4).
- `workspace_root`: Base working directory for repository checkouts.

---

## 3. Exclusive Stage Isolation (US-25)

Hardware micro-benchmarks (e.g. measuring RVV 1.0 throughput or A100 matrix jitter) require 100% of the SoC resources with zero background interference:
1. When a task arrives with `exclusive: true`, `WorkerAgent` verifies no other slots are active.
2. It acquires all execution permits, blocking any concurrent jobs.
3. The benchmark executes with exclusive access to CPU clusters, caches, and memory buses.
4. On completion, timeout, or cancellation, the exclusive permit is deterministically released, restoring normal multi-slot scheduling.

---

## 4. Hardware & Platform Invariants

1. **Bare-Metal Sandboxing**: Runs under isolated system user `action-runner` with `ProtectHome=read-only`.
2. **Git-Only Synchronization**: Always synchronizes code via Git; avoids non-atomic file sync (`rsync`).
3. **Target Toolchain Verification**: Directly integrates with native RISC-V Rust toolchains (`/var/lib/action-runner/.rustup`) and GFM table formatters.

---

## 5. Inter-Crate Dependencies

- **Imports**: `action-runner-ipc`, `tokio`, `tokio-tungstenite`, `arrow`, `thiserror`, `serde`
- **Consumers**: `action-runner-controller`
