# Model-Runner Documentation Portal

Welcome to the documentation portal for **Model-Runner**, a high-performance, distributed AI inference runtime and control plane engineered specifically for the **SpacemiT Key Stone K3 SoC** (16 heterogeneous 64-bit RISC-V cores across general-purpose and vector/matrix clusters, 32 GB unified memory).

Model-Runner delivers cycle-exclusive execution, systemd cgroup isolation, zero-flash-wear shared memory context caching, and hardware-accelerated RVV 1.0 / A100 IME compute kernels with native OpenAI and Anthropic Claude API compatibility.

---

## 📚 Portal Navigation

### 1. End-User Guides
Actionable walkthroughs for model ingestion, standalone benchmarking, and connecting AI clients and coding agents.
- [**Quickstart Guide**](quickstart.md) — 5-minute onboarding walkthrough: ingesting GGUF models from Hugging Face or Ollama, evaluating inference locally with `k3-diag`, starting system services, and connecting Python SDKs, cURL, and AI coding agents (Cline, Cursor, Roo-Code).
- [**Full Reference Manual**](manual.md) — Comprehensive technical reference: `k3-store` CLI commands, TOML configuration schema, OpenAI `/v1/chat/completions` protocol specifications, Anthropic Claude `/v1/messages` specifications, thinking blocks, tool calling, and full HTTP/CLI error mappings.

### 2. Operator Runbooks
Technical documentation for systems engineers and platform administrators managing production RISC-V deployments.
- [**Deployment & Maintenance Guide**](deployment.md) — Production architecture: systemd service isolation (`k3.slice`, `k3-kv`, `model-runner`), Linux cgroup v2 top-down delegation, conditional `/proc/set_ai_thread` registration, bounded 28 GiB `RLIMIT_MEMLOCK` ceiling, DuckDB catalog schema, and scheduled dual-gate garbage collection.
- [**Troubleshooting Guide**](troubleshooting.md) — Diagnostic procedures and incident runbooks for `K3Error` variants (`InsufficientLockableMemory`, `CapabilityMismatch`, `ContextLengthExceeded`, `QueueSaturated`), stale derived weight recovery, lock inspection with `k3-store who-uses`, and watchdog preemption.
- [**Hardware Tuning & Sizing Guide**](tuning.md) — Hardware-specific microarchitectural tuning for SpacemiT K3: Cluster 0 (`X100`, cores 0–7) vs Cluster 1 (`A100`, cores 8–15), core partition masks, KV cache arena sizing tables, admission queue depth, and dynamic idle core spillover.

### 3. Architecture & Developer Reference
In-depth crate architecture guides and machine-generated Rustdoc API documentation.
- [**Crate Reference Guides**](docs/crates/index.md) — Architecture and subsystem guide covering all 11 library crates and 3 binary executables across Model-Runner and ActionRunner CI.
- [**Unified Rustdoc API Reference**](api/index.html) — Machine-generated Rust API browser covering all 14 crate entries with full type signatures, traits, and search index.

---

## ⚡ Architecture at a Glance

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                       SpacemiT Key Stone K3 (16 Cores)                       │
├──────────────────────────────────────┬───────────────────────────────────────┤
│ Cluster 0: X100 General-Purpose Pool │  Cluster 1: A100 AI / Matrix Engine   │
│ Cores: 0 – 7 (Mask: 0x00FF)          │  Cores: 8 – 15 (Mask: 0xFF00)         │
│ 2.15 GHz Out-of-Order, VLEN = 256    │  1.80 GHz In-Order, VLEN = 1024       │
│                                      │                                       │
│ • Cores 6–7 (0x00C0): Active Control │ • Cores 8–15 (0xFF00): Matrix Compute │
│   (HTTP/SSE server, tokenization)    │ • XSMTVDotII (8×16 i8 → 8×8 i32)      │
│ • Core 5 (0x0020): Watchdog Monitor  │ • 8× 384 KiB Coupled TCM (3.0 MiB)    │
│ • Cores 0–5 (0x003F): General Compute│ • /proc/set_ai_thread registration    │
└──────────────────────────────────────┴───────────────────────────────────────┘
```

### Core Architectural Invariants:
1. **Zero Context Leakage**: Memory holder daemon (`k3-kv`) pre-faults and pins shared memory arenas (`memfd_create` + `mlock`). When compute workers restart or fail, context memory survives intact.
2. **Bounded Locked Memory**: `RLIMIT_MEMLOCK` is configured to a strict 28 GiB ceiling (`29360128 KB`) on 32 GiB hardware, preserving ~3.3 GiB strictly for the headless Linux kernel and OS services.
3. **Zero-SQLite Invariant**: All metadata, token budgets, model manifests, tuning profiles, and session states are managed using DuckDB (`duckdb`).
4. **Safe Dual-Gate Garbage Collection**: Physical weight reclamation (`k3-store gc`) is protected by Gate 1 (`flock`) and Gate 2 (`/proc/*/maps`), preventing unlinking of active weight files even when the control daemon is offline.
5. **Non-Blocking Control Plane**: Fast HTTP parsing, Jinja chat template application, prompt tokenization, and admission queue queries execute on dedicated control threads without ever blocking on long-running forward passes.

---

## 🔗 Related Repositories

- [**LMA1980/model-runner**](https://github.com/LMA1980/model-runner) — Top-level repository and workspace orchestration.
- [**k3-core**](https://github.com/LMA1980/k3-core) | [**k3-kv**](https://github.com/LMA1980/k3-kv) | [**k3-engine**](https://github.com/LMA1980/k3-engine) | [**k3-manager**](https://github.com/LMA1980/k3-manager)
- [**kernels-rvv**](https://github.com/LMA1980/kernels-rvv) | [**arch-synthetic**](https://github.com/LMA1980/arch-synthetic) | [**k3-tokenizer**](https://github.com/LMA1980/k3-tokenizer)
- [**ActionRunner-rs**](https://github.com/LMA1980/ActionRunner-rs) | [**ActionRunner-controller**](https://github.com/LMA1980/ActionRunner-controller) | [**ActionRunner-ipc**](https://github.com/LMA1980/ActionRunner-ipc) | [**ActionRunner-web**](https://github.com/LMA1980/ActionRunner-web)
