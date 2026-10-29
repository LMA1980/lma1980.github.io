# `k3-engine` Architecture & Crate Reference

**Crate**: `k3-engine`  
**Version**: `0.1.0` (Edition 2024, Rust 1.85)  
**Role**: Low-level compute runtime, thread group synchronization, compute worker binary (`k3-worker`), and diagnostic profiler (`k3-diag`)  
**Repository**: [`LMA1980/k3-engine`](https://github.com/LMA1980/k3-engine)  
**Rustdoc Reference**:
- [`k3_engine` API Reference](../../api/k3_engine/index.html)
- [`k3_worker` API Reference](../../api/k3_worker/index.html)
- [`k3_diag` API Reference](../../api/k3_diag/index.html)

---

## 1. Purpose & System Context

`k3-engine` is the compute engine responsible for high-performance neural network forward passes on SpacemiT Key Stone K3 hardware. It executes single-prompt inference using:
- Hardware-specialized RVV 1.0 vector loops and A100 Matrix Engine (IME) kernels via `kernels-rvv`.
- Ultra-low-latency thread synchronization barriers (`FutexBarrier`, `SpinBarrier`).
- Memory-locked model weight views (`LockedModelWeights`).
- Paged context memory cache views (`SingleSlotKvArena`).

`k3-engine` also produces two critical binary executables:
1. `k3-worker`: The dedicated compute daemon spawned by `k3-manager` for isolated forward-pass execution.
2. `k3-diag`: Standalone CLI diagnostic and benchmarking tool for profiling models across hardware clusters without running the control plane.

---

## 2. Key Public Types & Data Structures

### 2.1 `SinglePromptEngine`
The primary engine instance owning locked weights and thread pool:
```rust
pub struct SinglePromptEngine<R: ArchRecipe> {
    recipe: R,
    weights: Arc<LockedModelWeights>,
    worker_pool: WorkerPool,
    arena: Arc<SingleSlotKvArena>,
}
```

### 2.2 `WorkerPool` & Thread Synchronization Barriers
High-performance inter-thread coordination for parallel layer evaluation:
- `SpinBarrier`: Zero-sleep spinning barrier for ultra-low latency forward passes when cores are exclusively dedicated.
- `FutexBarrier`: Linux futex-based parking barrier minimizing CPU consumption during token generation pauses.

### 2.3 `LockedModelWeights`
Maintains `flock(fd, LOCK_SH)` advisory locks on mapped weight files to signal active inference to the garbage collector (`k3-store gc`), preventing premature unlinking.

---

## 3. Hardware Cluster Invariants

### 3.1 Cluster 0 (`X100`, Cores 0–7, `0x00FF`)
- Max compute threads: 6 (cores 0–5, mask `0x003F`).
- Cores 6–7 (`0x00C0`) are strictly reserved for the control plane.
- Cores 0–7 execute RVV 1.0 (`VLEN=256`). They **trap with `SIGILL`** if `XSMTVDotII` matrix instructions are executed.

### 3.2 Cluster 1 (`A100`, Cores 8–15, `0xFF00`)
- Max compute threads: 8 (cores 8–15, mask `0xFF00`).
- Supports RVV 1.0 (`VLEN=1024`) and `XSMTVDotII` matrix instructions (`smt.vpack.vv` and `smt.vmadot`, `8x16 i8` multiplication).
- **SpacemiT Kernel Requirement**: Any thread binding to cores 8–15 must write its kernel thread ID (`SYS_gettid`) to `/proc/set_ai_thread` before calling `sched_setaffinity`.

---

## 4. Binary Executables

<a id="worker-process-binary"></a>
### 4.1 Worker Process Binary (`k3-worker`)
`k3-worker` is spawned by `k3-manager` into a dedicated cgroup leaf (`.../engines/<model>`):
```bash
k3-worker --model-id <id> --weights-fd <fd> --kv-fd <fd> --affinity <mask> --threads <n>
```
- Operates under strict network isolation (no socket access).
- Reads tokens from UDS IPC, executes forward passes, and writes logits/tokens back to the manager.
- Preemptible by `HealthSupervisor` watchdog if pass deadlines are breached.

<a id="diagnostic-cli-binary"></a>
### 4.2 Diagnostic CLI Binary (`k3-diag`)
Standalone CLI tool for benchmarking and validating models on hardware:
```bash
k3-diag --model /var/lib/k3/blobs/sha256/<hash> --prompt "Benchmark prompt" \
        --cluster both --split phase --ime on --threads 8 --cores 0xFF00 \
        --n-ctx 2048 --repeat 5 --summary --export-profile /tmp/cost_profile.json
```
- **Exit Codes**: Maps `K3Error` directly to distinct exit codes (`10`: CapabilityMismatch, `11`: InsufficientLockableMemory, `12`: ContextLengthExceeded, `13`: AffinityError, `14`: TensorBoundsError, `15`: RoutingUnavailable, `23`: QueueSaturated).
- **Conservative Memory Mode**: Supports `--n-ctx 64` to run cleanly in unprivileged CI environments.

---

## 5. Inter-Crate Dependencies

- **Imports**: `k3-core`, `kernels-rvv`, `libc`, `nix`, `clap`, `serde`, `serde_json`
- **Consumers**: `k3-manager` (spawns `k3-worker` and parses `k3-diag` profiles)
