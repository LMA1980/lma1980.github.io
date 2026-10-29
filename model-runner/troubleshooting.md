# Model-Runner Operator Troubleshooting Guide

This guide provides diagnostic procedures and resolution runbooks for operational errors, memory exhaustion, architecture rejections, queue saturation, and unresponsive worker recovery on the SpacemiT Key Stone K3 platform.

---

## 1. Quick Diagnostic Triage

When an incident occurs, run the following triage commands:

```bash
# 1. Check system service status
systemctl status k3-kv.service model-runner.service

# 2. Inspect active journal logs
journalctl -u model-runner.service -n 100 --no-pager

# 3. Inspect locked memory and available RAM
cat /proc/meminfo | grep -E "MemTotal|MemAvailable|Mlocked"

# 4. Check active cgroup placement
cat /sys/fs/cgroup/k3.slice/control/cgroup.procs
cat /sys/fs/cgroup/k3.slice/control/cpuset.cpus

# 5. List registered blobs and active reference counts
k3-store list blobs
```

---

## 2. Diagnostic Runbook for `K3Error` Variants

### 2.1 `InsufficientLockableMemory`

- **Verbatim Error**:
  ```
  [insufficient_lockable_memory] required <R> bytes (weights: <W> bytes, kv: <K> bytes) exceeds lockable capacity (available RAM: <A> bytes, RLIMIT_MEMLOCK: <M> bytes)
  ```
- **Diagnostic Code**: `insufficient_lockable_memory` (Exit code 11)
- **Root Cause**: The combined memory footprint of locked model weights plus the pre-reserved KV cache arena (`weights + n_ctx * slots * block_size`) exceeds available physical RAM or the bounded 28 GiB `RLIMIT_MEMLOCK` ceiling.
- **Diagnostic Procedure**:
  ```bash
  # Check locked memory limit of the running process
  prlimit --pid $(pgrep -f "k3-worker|k3-manager") --memlock

  # Inspect memory consumption of all loaded models
  k3-store list blobs
  ```
- **Remediation**:
  1. Verify `/etc/security/limits.d/99-modelrunner.conf` has `29360128` (28 GiB).
  2. Reduce model context window (`n_ctx`) in the operator tuning profile (e.g. reduce from 8192 to 2048 or 4096).
  3. Unload inactive models via the control-plane API (`AdminCommand::UnregisterModel`) or unlink the model alias (`models/<source>/<namespace>/<name>/<tag>`) via DuckDB catalog / CAS API (`remove_alias`) to decrement blob reference counts.
  4. Run `k3-store gc` to reclaim orphaned weights.
  5. In diagnostic or unit test environments, set `n_ctx = 64` per `AGENTS.md` §5.

---

### 2.2 `CapabilityMismatch`

- **Verbatim Error**:
  ```
  [capability_mismatch] unsupported architecture '<arch>': <reason>
  ```
- **Diagnostic Code**: `capability_mismatch`
- **Root Cause**: The model format, tensor quantization scheme, or architecture revision is not supported by compiled runtime execution recipes in `k3-engine` or `k3-kernels-rvv`.
- **Diagnostic Procedure**:
  ```bash
  # Inspect model manifest and quantization format
  k3-store inspect <alias_or_digest>
  ```
- **Remediation**:
  1. Ensure weights are quantized in supported formats: `Q4_K_M`, `Q8_0`, `F16`, or `F32`.
  2. For synthetic benchmarking, ensure `architecture_id: "synthetic"`.
  3. For LLM execution on SpacemiT A100 matrix cores, verify the model architecture has a compiled IME recipe (e.g. `qwen3`).
  4. If importing from HuggingFace, verify that the architecture recipe revision matches the runtime.

---

### 2.3 `ContextLengthExceeded`

- **Verbatim Error**:
  ```
  [context_length_exceeded] sequence length <R> tokens exceeds configured n_ctx limit of <M> tokens
  ```
- **Diagnostic Code**: `context_length_exceeded` (HTTP 400 Bad Request)
- **Root Cause**: The incoming prompt plus requested completion tokens exceeds the pre-allocated fixed context arena bound `n_ctx` (ADR-027). The system rejects the request immediately rather than silently truncating prompt tokens.
- **Remediation**:
  1. Truncate prior conversational history on the client side.
  2. Enable client-side sliding window context trimming.
  3. If memory headroom permits, increase `n_ctx` in the model's tuning profile via the control plane and reload.

---

### 2.4 `QueueSaturated`

- **Verbatim Error**:
  ```
  [queue_saturated] model '<M>' queue depth <D> reached ceiling <C>
  ```
- **Diagnostic Code**: `queue_saturated` (HTTP 429 Too Many Requests / HTTP 529 Overloaded)
- **Response Headers**: `Retry-After: 5`
- **Root Cause**: The admission queue for the target model has reached its configured capacity ceiling (default: 64 pending requests). Compute workers are fully saturated.
- **Remediation**:
  1. Respect the `Retry-After` header in API clients and coding agents (Cline, Cursor, Roo-Code).
  2. Inspect compute worker CPU utilization on cores 8–15 (A100) or cores 0–5 (X100).
  3. Enable dynamic idle core lending (`lend_idle_cores = true` / `borrow_idle_cores = true`) to borrow cores from idle models during forward passes.
  4. Increase `queue_depth_cap` in the model configuration if client wait latency is acceptable.

---

### 2.5 `AffinityError`

- **Verbatim Error**:
  ```
  [affinity_error] worker placement on '<model>' encroaches on dedicated active control cores 0x00C0
  ```
- **Root Cause**: A compute worker requested core allocation overlapping dedicated active control cores 6–7 (`0x00C0`) or exceeding the 6-core X100 compute cap (`0x003F`).
- **Remediation**:
  1. Ensure compute workers targeting Cluster 0 (X100) specify a mask within `0x003F` (cores 0–5, max 6 threads).
  2. Ensure workers targeting Cluster 1 (A100) specify `0xFF00` (cores 8–15, max 8 threads).

---

## 3. Stale Derived Weight Layout Resolution

When a runtime upgrade updates an architecture recipe version (e.g. breaking IME tile layout changes), cached derived blobs (`ime_tile_8x16`) are marked `stale`:

- **Case 1: Original Raw Weights Kept (`RetentionPolicy::Keep`)**:
  - The runtime automatically invokes `rayon` parallel repacking and rebuilds the derived layout from original source weights without operator intervention.
- **Case 2: Original Raw Weights Purged (`RetentionPolicy::PurgeImmediate`)**:
  - The runtime emits an operational advisory:
    ```
    Derived weights for ime_tile_8x16 from source digest <digest> are stale (built for recipe version 1.0.0, current runtime is 2.0.0), and original source weights have been purged. Please re-acquire the source model.
    ```
  - **Resolution**: Re-acquire the source model weights via the external model source adapter or ingest them into the content-addressed store.

---

## 4. Unresponsive Worker Preemption & Watchdog Recovery

Model-Runner isolates the health watchdog on a dedicated spare recovery core (core 5, `0x0020`), decoupled from compute cores:

```
[Forward Pass Stall / Infinite Loop]
               │
               ▼
   [HealthSupervisor Watchdog on Core 5]
   - Heartbeat deadline breach (>5000 ms)
   - Forward-pass deadline breach (>30000 ms)
               │
               ▼
   [Send SIGTERM to Worker PID] ──(500 ms)──> [Send SIGKILL & waitpid]
               │
               ▼
   [Spawn Clean Replacement Worker]
   - Re-attach to surviving k3-kv arena via SCM_RIGHTS
   - Resume forward-pass execution without board reboot
```

### Checking Recovery Audit Logs:
```bash
journalctl -u model-runner.service -g "HealthSupervisor"
# Example log:
# [HealthSupervisor] Worker 'qwen2.5-7b' (pid 14205) unresponsive after 30002 ms.
# [HealthSupervisor] Terminated pid 14205 via SIGKILL. Reaped exit code.
# [HealthSupervisor] Spawned replacement worker (pid 14312, gen 2) re-attached to k3-kv arena. Resuming generation.
```

---

## 5. Active Holder Inspection (`k3-store who-uses`)

To inspect why a blob cannot be garbage collected, or to identify which process holds an open file descriptor or memory mapping:

```bash
k3-store who-uses 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08
```

### Sample Output:
```
Blob: 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08
Path: /var/lib/k3/blobs/sha256/9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08
Size: 4325601280 bytes
References: 1 active (["huggingface/Qwen/Qwen2.5-7B/latest"])
Gate 1 (flock): SHARED LOCK HELD (active worker)
Gate 2 (mappings): 1 active process mapping(s)
  - PID 14205 (k3-worker) mapped at 0x7f8a10000000-0x7f8b10000000 (r--p)
Status: IN USE (unsafe to delete)
```
