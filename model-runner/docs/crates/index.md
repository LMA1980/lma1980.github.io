# Model-Runner, ActionRunner & MuObserve Crate Architecture Matrix

This directory contains in-depth architectural and integration reference guides for the core crates and binary executables composing the **Model-Runner** distributed AI inference ecosystem, the **ActionRunner** bare-metal CI execution sidecar, and the **MuObserve** distributed observability, regression analytics, and Antigravity MCP suite on the SpacemiT Key Stone K3 heterogeneous RISC-V SoC.

For machine-generated Rustdoc method signatures, trait implementations, and field-level documentation, visit the [Unified Rustdoc API Reference](../../api/).

______________________________________________________________________

## 1. System Crate Matrix

| Crate                          | Role                           | Type               | Target Hardware / Cores                | Memory / IPC Model                          | Architecture Guide                                                       | API Reference                                                               |
| ------------------------------ | ------------------------------ | ------------------ | -------------------------------------- | ------------------------------------------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| **`k3-core`**                  | Foundational Types & Context   | Library            | Cluster 0 & 1 (`0xFFFF`)               | Zero-copy `TensorView`, bitmasks            | [k3-core.md](k3-core.md)                                                 | [`k3_core`](../../api/k3_core/index.html)                                   |
| **`k3-kv`**                    | Context Memory Holder          | Daemon / Lib       | Systemd isolated                       | `mlock`ed `memfd`, `SCM_RIGHTS` UDS         | [k3-kv.md](k3-kv.md)                                                     | [`k3_kv`](../../api/k3_kv/index.html)                                       |
| **`k3-engine`**                | Compute Runtime                | Library            | Cores 0–5 (`0x003F`) / 8–15 (`0xFF00`) | `FutexBarrier`, paged KV arena              | [k3-engine.md](k3-engine.md)                                             | [`k3_engine`](../../api/k3_engine/index.html)                               |
| **`k3-worker`**                | Worker Process                 | Executable         | Delegated cgroup leaf                  | Single-prompt forward pass                  | [k3-engine.md#worker-process-binary](k3-engine.md#worker-process-binary) | [`k3_worker`](../../api/k3_worker/index.html)                               |
| **`k3-diag`**                  | Diagnostic & Profiler          | Executable         | Cluster 0, 1, or both                  | Local benchmarking, jitter                  | [k3-engine.md#diagnostic-cli-binary](k3-engine.md#diagnostic-cli-binary) | [`k3_diag`](../../api/k3_diag/index.html)                                   |
| **`k3-manager`**               | Control Plane & Orchestrator   | Daemon / Lib       | Cores 6–7 (`0x00C0`)                   | DuckDB catalog, HTTP/SSE, watchdog          | [k3-manager.md](k3-manager.md)                                           | [`k3_manager`](../../api/k3_manager/index.html)                             |
| **`k3-store`**                 | Storage Administration CLI     | Executable         | Host CLI                               | Dual-gate GC, `who-uses` locks              | [k3-manager.md#storage-cli-binary](k3-manager.md#storage-cli-binary)     | [`k3_store`](../../api/k3_store/index.html)                                 |
| **`kernels-rvv`**              | Vector & Matrix Acceleration   | Library            | RVV 1.0 & A100 IME                     | VLA strip-mining, `8x16 i8` tiles           | [k3-kernels-rvv.md](k3-kernels-rvv.md)                                   | [`kernels_rvv`](../../api/kernels_rvv/index.html)                           |
| **`arch-synthetic`**           | Synthetic Architecture Recipe  | Library            | Pure CPU / Testing                     | Reference forward pass, argmax              | [arch-synthetic.md](arch-synthetic.md)                                   | [`arch_synthetic`](../../api/arch_synthetic/index.html)                     |
| **`k3-tokenizer`**             | Tokenization & Chat Templates  | Library            | Cores 6–7 (Control threads)            | Streaming detokenizer, Jinja templates      | [k3-tokenizer.md](k3-tokenizer.md)                                       | [`k3_tokenizer`](../../api/k3_tokenizer/index.html)                         |
| **`action-runner`**            | Bare-Metal CI Worker           | Daemon / Lib       | Bare-metal SpacemiT K3                 | Exclusive stage lock, process isolation     | [action-runner.md](action-runner.md)                                     | [`action_runner`](../../api/action_runner/index.html)                       |
| **`action-runner-controller`** | Webhook Ingress & Scheduler    | Daemon / Lib       | Edge controller                        | Coalescing FIFO, DuckDB metrics             | [action-runner-controller.md](action-runner-controller.md)               | [`action_runner_controller`](../../api/action_runner_controller/index.html) |
| **`action-runner-ipc`**        | Zero-Copy Wire Protocol        | Library            | Transport layer                        | `0x41524950` framing, Fory, Arrow           | [action-runner-ipc.md](action-runner-ipc.md)                             | [`action_runner_ipc`](../../api/action_runner_ipc/index.html)               |
| **`action-runner-web`**        | Leptos WASM Dashboard          | Web App / Lib      | Client browser                         | Leptos CSR, WebSocket telemetry             | [action-runner-web.md](action-runner-web.md)                             | [`action_runner_web`](../../api/action_runner_web/index.html)               |
| **`muobserve-ipc`**            | Wire Protocols & Arrow Schemas | Library            | Transport layer (`0xFFFF`)             | 24-byte `MUOB` framing, Arrow, Fory         | [muobserve-ipc.md](muobserve-ipc.md)                                     | [`muobserve_ipc`](../../api/muobserve_ipc/index.html)                       |
| **`muobserve-collector`**      | Sandboxed Node Edge Collector  | Daemon / Lib       | Edge nodes / Loopback                  | Ring-buffer WAL (`256 MiB`), mTLS forwarder | [muobserve-collector.md](muobserve-collector.md)                         | [`muobserve_collector`](../../api/muobserve_collector/index.html)           |
| **`muobserve`**                | Central Observability & MCP    | Daemon / Lib / Bin | Central hub (Port 8443, SSE)           | 3-tier DuckDB/Parquet lake, 10 MCP tools    | [muobserve.md](muobserve.md)                                             | [`muobserve`](../../api/muobserve/index.html)                               |

______________________________________________________________________

## 2. Dependency Graph & Boundary Hierarchy

```
                            [ Client Applications / AI Agents ]
                                          │
                        (OpenAI / Claude HTTP/SSE REST APIs)
                                          │
                                          ▼
                                   ┌──────────────┐
                                   │  k3-manager  │──(DuckDB Catalog)
                                   └──────┬───────┘
                                          │
                ┌─────────────────────────┼─────────────────────────┐
                ▼                         ▼                         ▼
         ┌──────────────┐          ┌──────────────┐          ┌──────────────┐
         │ k3-tokenizer │          │    k3-kv     │          │  k3-worker   │
         └──────────────┘          └──────┬───────┘          └──────┬───────┘
                                          │ (SCM_RIGHTS UDS)        │
                                          └─────────────────────────┘
                                                    │
                                                    ▼
                                             ┌──────────────┐
                                             │  k3-engine   │
                                             └──────┬───────┘
                                                    │
                                      ┌─────────────┴─────────────┐
                                      ▼                           ▼
                               ┌──────────────┐            ┌──────────────┐
                               │   k3-core    │            │ kernels-rvv  │
                               └──────────────┘            └──────────────┘

─────────────────────────────────────────────────────────────────────────────
CI, Observability & Analytics Subsystem:

[ GitHub Webhook ] ──> [ action-runner-controller ] ──(Fory RPC)
                                │                              │
                        (action-runner-ipc)                    ▼
                                │                     ┌──────────────────┐
                                ▼                     │    MuObserve     │
                       [ action-runner ]              │ (Central Server) │
                                │                     │  • hot.duckdb    │
                       (OTLP / MUOB Arrow)            │  • Zstd Parquet  │
                                │                     │  • v_* Views     │
                                ▼                     │  • Regression    │
                    [ muobserve-collector ]           └────────┬─────────┘
                                │                              │
                        (step-ca mTLS)                         │
                                │                              │
                                └──────────────────────────────┘
                                                               │
                                         ┌─────────────────────┴─────────────────────┐
                                         │ (Model Context Protocol: stdio & HTTP/SSE)│ (WebSocket Telemetry)
                                         ▼                                           ▼
                             [ Antigravity AI Agent ]                     [ action-runner-web ]
                             (10 MuObserve MCP Tools)                     (Leptos CSR WASM)
```

______________________________________________________________________

## 3. Guiding Principles & Workspace Invariants

1. **Cycle-Exclusive Single-Prompt Execution**: Compute forward passes execute with 100% thread dedication and zero mid-pass preemption.
1. **Strict Hardware Cluster Isolation**:
   - **Cluster 0 (`X100`, Cores 0–7, `0x00FF`)**: Out-of-order 2.15 GHz general-purpose cores. Cores 6–7 (`0x00C0`) are strictly dedicated active control threads. Core 5 (`0x0020`) is reserved for the spare recovery watchdog. Compute workers on X100 are strictly capped to cores 0–5 (`0x003F`, max 6 threads).
   - **Cluster 1 (`A100`, Cores 8–15, `0xFF00`)**: In-order 1.80 GHz matrix acceleration cores with `XSMTVDotII` instruction support. Up to 8 compute threads (`0xFF00`). Regular threads must write TID to `/proc/set_ai_thread` before binding.
1. **Bounded Memory Ceiling**: `RLIMIT_MEMLOCK` is pinned to 28 GiB (`29360128 KB`) preserving ~3.3 GiB OS headroom on 32 GiB hardware.
1. **Zero-SQLite Invariant**: All metadata, CAS catalogs, token budgets, tuning profiles, and test metrics use DuckDB (`duckdb`).
1. **Rust Integer Discipline**: `usize` is reserved strictly for collection indexing, buffer lengths, and memory allocation; `u32` is used for domain counters, token counts, IDs, slots, and network protocol framing.
