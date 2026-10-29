# `k3-kv` Architecture & Crate Reference

**Crate**: `k3-kv`  
**Version**: `0.1.0` (Edition 2024, Rust 1.85)  
**Role**: Policy-free context memory holder daemon and shared memory arena manager  
**Repository**: [`LMA1980/k3-kv`](https://github.com/LMA1980/k3-kv)  
**Rustdoc Reference**: [`k3_kv` API Reference](../../api/k3_kv/index.html)

---

## 1. Purpose & System Context

`k3-kv` is a lightweight, policy-free daemon designed to hold KV cache context memory across worker crashes, restarts, and preemptions.

In traditional LLM runtimes, when a worker process crashes due to a forward-pass anomaly or memory fault, the entire conversational context is lost, requiring expensive prompt recomputation. `k3-kv` decouples context memory from compute:
1. `k3-kv` allocates anonymous shared memory arenas via `memfd_create()`.
2. Memory pages are pre-faulted and pinned in physical RAM using `mlock()`.
3. Memory file descriptors are handed off to compute workers (`k3-worker`) over Unix Domain Sockets using `SCM_RIGHTS`.
4. If a compute worker crashes, the memory arena remains intact in `k3-kv`. When a replacement worker is spawned, it re-attaches to the existing `memfd` descriptor and resumes inference immediately without context loss.

---

## 2. Key Public Types & Data Structures

### 2.1 `KvHolder`
The core state container managing active shared-memory arenas:
```rust
pub struct KvHolder {
    arenas: RwLock<HashMap<ArenaId, SharedArena>>,
    config: ArenaAllocationConfig,
}
```

### 2.2 `ComputedArenaLayout`
Computes exact byte requirements for paged KV cache allocation:
```rust
pub struct ComputedArenaLayout {
    pub total_bytes: usize,
    pub block_size_tokens: usize,
    pub total_blocks: usize,
    pub bytes_per_block: usize,
    pub num_layers: usize,
    pub num_heads: usize,
    pub head_dim: usize,
}
```

### 2.3 `ArenaAllocationConfig`
Enforces memory bounding and resource limits:
- `max_total_bytes`: Maximum aggregate memory across all arenas (bounded by 28 GiB ceiling).
- `default_block_size`: 16 tokens (`BLOCK_SIZE_TOKENS = 16`).
- `socket_path`: `/run/k3/kv.sock` (or user-configured UDS).

---

## 3. Protocol & IPC Mechanism (`SCM_RIGHTS`)

The daemon communicates with `k3-manager` and `k3-worker` via Unix Domain Sockets using ancillary control messages (`recvmsg` / `sendmsg`):

```
k3-manager                       k3-kv                          k3-worker
    │                              │                                │
    ├── AllocateArena(layout) ────>│                                │
    │<── ArenaAllocated(id) ───────┤                                │
    │                              │                                │
    ├── RequestDescriptor(id) ────>│                                │
    │<── SCM_RIGHTS(memfd) ────────┤                                │
    │                                                               │
    ├── Spawn Worker & pass fd via SCM_RIGHTS ─────────────────────>│
    │                                                               │ (mmap memfd)
    │                                                               │ Zero-copy R/W
```

---

## 4. Hardware & System Invariants

1. **`LimitMEMLOCK` Ceiling**: `k3-kv` runs under a strict bounded memlock ceiling (`29360128 KB` / 28 GiB) configured in `/etc/security/limits.d/99-modelrunner.conf` to preserve ~3.3 GiB headroom for the OS and kernel slab.
2. **Systemd Sandboxing**: Runs as an isolated service unit (`k3-kv.service`) in `k3.slice` with `PrivateTmp=yes`, `ProtectSystem=strict`, and `CapabilityBoundingSet=CAP_IPC_LOCK`.
3. **Zero Policy**: `k3-kv` contains no model loading, tokenization, or scheduling logic. It performs pure arena lifecycle management.

---

## 5. Inter-Crate Dependencies

- **Imports**: `k3-core`, `libc`, `nix`, `tokio`, `thiserror`
- **Consumers**: `k3-manager`, `k3-engine`
