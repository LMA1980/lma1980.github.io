# Model-Runner Operator Deployment & Maintenance Guide

This guide describes production deployment, resource isolation, systemd orchestration, storage maintenance, and safe garbage collection for the Model-Runner platform on SpacemiT Key Stone K3 hardware (16 heterogeneous RISC-V cores, 32 GB unified memory).

---

## 1. Systemd Architecture & Service Units

Model-Runner decouples memory holding from control-plane orchestration and compute worker execution across dedicated systemd service units contained within `k3.slice`.

```
/sys/fs/cgroup/k3.slice/
├── control/                     # model-runner.service (cores 6–7)
│   ├── cpuset.cpus = "6-7"
│   └── cgroup.procs = [pid_manager]
├── kv/                          # k3-kv.service (isolated arena holder)
│   └── cgroup.procs = [pid_kv]
└── engines/                     # Delegated compute worker leaves
    ├── qwen2.5-7b/              # k3-worker (cores 8–15 on A100)
    │   ├── cpuset.cpus = "8-15"
    │   └── cgroup.procs = [pid_worker_1]
    └── synthetic-demo/          # k3-worker (cores 0–5 on X100)
        ├── cpuset.cpus = "0-5"
        └── cgroup.procs = [pid_worker_2]
```

### 1.1 Slice Definition (`/etc/systemd/system/k3.slice`)

```ini
[Unit]
Description=Model-Runner Unified Isolation Slice
Documentation=https://lma1980.github.io/model-runner/
Before=slices.target

[Slice]
CPUAccounting=yes
MemoryAccounting=yes
TasksAccounting=yes
```

### 1.2 Policy-Free KV Memory Holder (`/etc/systemd/system/k3-kv.service`)

The KV holder service allocates and pre-faults shared-memory arenas via `memfd_create` and `mlock`. It contains zero scheduling policy and does not terminate when workers or managers restart.

```ini
[Unit]
Description=Model-Runner KV Context Memory Holder Daemon
Documentation=https://lma1980.github.io/model-runner/
After=network.target k3.slice
PartOf=k3.slice

[Service]
Type=simple
Slice=k3.slice
User=k3
Group=k3
RuntimeDirectory=k3
RuntimeDirectoryMode=0755
ExecStart=/usr/local/bin/k3-kv --socket /run/k3/kv.sock
Restart=always
RestartSec=2

# Hard memory bounds: 28 GiB ceiling, preserving ~3.3 GiB OS headroom
LimitMEMLOCK=29360128
MemoryMax=28G

# Sandboxing
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/run/k3
PrivateTmp=yes
CapabilityBoundingSet=CAP_IPC_LOCK

[Install]
WantedBy=multi-user.target
```

### 1.3 Compute Worker Daemon (`/etc/systemd/system/model-runner.service`)

The compute worker service runs the dedicated `k3-worker` daemon, executing neural network forward passes with pinned core affinity and attaching to `k3-kv` shared-memory arenas over Unix Domain Sockets:

```ini
[Unit]
Description=Model-Runner Compute Worker Daemon
Documentation=https://lma1980.github.io/model-runner/
Requires=k3-kv.service
After=k3-kv.service k3.slice
PartOf=k3.slice

[Service]
Type=simple
Slice=k3.slice
User=k3
Group=k3
RuntimeDirectory=k3
RuntimeDirectoryMode=0755
Environment=K3_STORE_ROOT=/var/lib/k3
Environment=K3_CATALOG_PATH=/var/lib/k3/catalog.duckdb
Environment=RUST_LOG=info
ExecStart=/usr/local/bin/k3-worker --socket /run/k3/worker.sock --listen --model /var/lib/k3/blobs/sha256/b7e9411c52109403a73c1f4e04f981e1136b6f38aa70494cf0785f79a0b98bc9 --cluster x100 --threads 6
Restart=always
RestartSec=2

# Locked memory ceiling & delegation
LimitMEMLOCK=29360128
MemoryMax=28G

# Sandboxing & Storage Access
ProtectSystem=full
ProtectHome=read-only
ReadWritePaths=/run/k3 /var/lib/k3 /sys/fs/cgroup/k3.slice
PrivateTmp=yes
CapabilityBoundingSet=CAP_SYS_NICE CAP_SYS_RESOURCE CAP_IPC_LOCK

[Install]
WantedBy=multi-user.target
```

### 1.4 Scheduled Storage Garbage Collection (`k3-store-gc.service` & `.timer`)

```ini
# /etc/systemd/system/k3-store-gc.service
[Unit]
Description=Model-Runner Safe Storage Garbage Collection Sweep
Documentation=https://lma1980.github.io/model-runner/
After=local-fs.target

[Service]
Type=oneshot
User=k3
Group=k3
ExecStart=/usr/local/bin/k3-store gc --store-root /var/lib/k3
ProtectSystem=full
ReadWritePaths=/var/lib/k3
```

```ini
# /etc/systemd/system/k3-store-gc.timer
[Unit]
Description=Daily Model-Runner Storage Garbage Collection Timer
Documentation=https://lma1980.github.io/model-runner/

[Timer]
OnCalendar=*-*-* 03:00:00 UTC
Persistent=true

[Install]
WantedBy=timers.target
```

---

## 2. Linux Cgroup v2 Isolation & Top-Down Delegation

Model-Runner enforces hardware core isolation using native cgroup v2 domain controllers without container runtimes (runc/Docker):

1. **Top-Down Controller Delegation**: intermediate ancestor directories between `/sys/fs/cgroup/k3.slice` and `.../engines/<model>` strictly write `+cpuset` to `cgroup.subtree_control` in top-down hierarchy order before creating leaf nodes.
2. **Control Leaf Placement**: `k3-manager` moves its process ID into `/sys/fs/cgroup/k3.slice/control/cgroup.procs` and restricts `cpuset.cpus` to cores `6-7` (`0x00C0`), guaranteeing uninterrupted control-plane execution during forward-pass saturation.
3. **Engine Leaf Placement**: when spawning a worker process, `k3-manager` creates `/sys/fs/cgroup/k3.slice/engines/<model_id>`, writes the assigned physical core list to `cpuset.cpus` (e.g. `0-5` for X100, `8-15` for A100), and writes the worker PID to `cgroup.procs`.
4. **Automatic OS Affinity Fallback**: if running in unprivileged test harnesses, non-Linux development hosts, or if `/sys/fs/cgroup` returns `EACCES` / `ENOENT`, the runtime automatically falls back to `sched_setaffinity` syscalls.

---

## 3. SpacemiT HMP Kernel Invariant: `/proc/set_ai_thread`

On the SpacemiT vendor Linux kernel (`spacemit-hmp`), threads binding to Cluster 1 (`A100`, cores `8–15`, mask `0xFF00`) must switch from `HMP_REGULAR` to `HMP_AI` mode:

- **Invariant**: Any worker process or thread pinning to cores 8–15 **must** write its thread ID (`SYS_gettid`) to `/proc/set_ai_thread` before calling `sched_setaffinity`.
- Attempting to bind regular threads to cores 8–15 without this registration returns `EINVAL`.
- On vanilla Linux kernels where `/proc/set_ai_thread` does not exist, the runtime skips this registration conditionally.

---

## 4. Memory Bounds: Bounded `RLIMIT_MEMLOCK` Ceiling

Setting `RLIMIT_MEMLOCK` to `unlimited` on embedded hardware risks catastrophic hard lockups: if 100% of RAM is locked by user space, Linux slab allocators cannot allocate page tables, network buffers, or SSH shells.

### 4.1 Headroom Budget (32 GiB Board)

| Component | Allocation | Rationale |
|---|---|---|
| **Linux Kernel & OS Headroom** | `3.3 GiB` – `4.0 GiB` | Kernel slab, TCP buffers, page tables, systemd, DuckDB WAL |
| **Model Weights & KV Arenas** | `28.0 GiB` (`29,360,128 KB`) | Bounded locked ceiling (`LimitMEMLOCK`) |

### 4.2 Security Limits Configuration (`/etc/security/limits.d/99-modelrunner.conf`)

```ini
# /etc/security/limits.d/99-modelrunner.conf
# Preserves ~3.3 GiB OS headroom on 32 GiB SpacemiT K3 boards
k3       soft   memlock   29360128
k3       hard   memlock   29360128
```

Verify the limits under the target service account:
```bash
sudo -u k3 bash -c "ulimit -l"
# Expected output: 29360128
```

---

## 5. Content-Addressed Model Store Layout

The store root defaults to `/var/lib/k3` (configurable via `K3_STORE_ROOT` or `--store-root`):

```
/var/lib/k3/
├── catalog.duckdb               # Relational catalog & session metadata
├── catalog.duckdb.wal           # DuckDB write-ahead log
├── blobs/
│   └── sha256/
│       ├── 9f86d081884c7d659a2f... # Immutable model weights (0644)
│       └── a4b1c2d3e4f506172839... # Converted / derived weight layouts
├── manifests/
│   └── sha256/
│       └── 3b7c8d9e0f1a2b3c4d5e...json # Canonical model metadata manifests
├── models/                      # Human-browsable relative symlink tree
│   └── huggingface/
│       └── Qwen/
│           └── Qwen2.5-7B-Instruct/
│               └── latest -> ../../../../manifests/sha256/3b7c8d9e...json
├── staging/                     # Atomic download staging (UUID.part)
└── derived/                     # Hardware-repacked IME tile layouts (8x16 i8)
```

### Security & Path Invariants:
- All path components (source, namespace, name, tag) are validated against directory traversal (`..`, `.`, `/`, `\`, control characters, null bytes).
- Maximum path component length: 128 characters.
- Weight files are addressed strictly by 64-character lowercase SHA-256 hexadecimal digests (`^[a-f0-9]{64}$`).
- Downloaded files are verified in `staging/` before atomic `rename()` promotion into `blobs/sha256/`.

---

## 6. DuckDB Catalog Schema & Maintenance

Model-Runner enforces a strict **Zero-SQLite Invariant**: all metadata, token budgets, tuning profiles, single-row session histories, and blob reference counts reside in DuckDB (`catalog.duckdb`).

### 6.1 Schema DDL Summary

```sql
CREATE TABLE tenants (id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at BIGINT NOT NULL);
CREATE TABLE projects (id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL REFERENCES tenants(id), name TEXT NOT NULL, token_budget BIGINT, created_at BIGINT NOT NULL);
CREATE TABLE tuning_profiles (model_id TEXT PRIMARY KEY, profile_json TEXT NOT NULL, updated_at BIGINT NOT NULL);
CREATE TABLE session_last_turns (session_id TEXT PRIMARY KEY, project_id TEXT NOT NULL REFERENCES projects(id), tenant_id TEXT NOT NULL REFERENCES tenants(id), model_id TEXT NOT NULL, prompt TEXT NOT NULL, response TEXT NOT NULL, prompt_tokens BIGINT NOT NULL, completion_tokens BIGINT NOT NULL, parameters_json TEXT NOT NULL, updated_at BIGINT NOT NULL);
CREATE TABLE model_blobs (digest TEXT PRIMARY KEY, size_bytes BIGINT NOT NULL, blob_type TEXT NOT NULL, created_at BIGINT NOT NULL, last_accessed_at BIGINT NOT NULL, ref_count INTEGER NOT NULL DEFAULT 0);
CREATE TABLE model_manifests (manifest_digest TEXT PRIMARY KEY, weight_digest TEXT NOT NULL REFERENCES model_blobs(digest), format TEXT NOT NULL, architecture_id TEXT NOT NULL, recipe_version TEXT NOT NULL, quantization TEXT NOT NULL, context_length BIGINT NOT NULL, license TEXT, origin TEXT, manifest_json TEXT NOT NULL, created_at BIGINT NOT NULL);
CREATE TABLE model_aliases (alias_id TEXT PRIMARY KEY, source TEXT NOT NULL, namespace TEXT NOT NULL, name TEXT NOT NULL, tag TEXT NOT NULL, manifest_digest TEXT NOT NULL REFERENCES model_manifests(manifest_digest), weight_digest TEXT NOT NULL REFERENCES model_blobs(digest), alias_path TEXT NOT NULL, created_at BIGINT NOT NULL);
CREATE TABLE derived_blobs (derived_digest TEXT PRIMARY KEY REFERENCES model_blobs(digest), source_digest TEXT NOT NULL REFERENCES model_blobs(digest), recipe_version TEXT NOT NULL, target_layout TEXT NOT NULL, status TEXT NOT NULL, created_at BIGINT NOT NULL);
CREATE TABLE blob_references (ref_id TEXT PRIMARY KEY, blob_digest TEXT NOT NULL REFERENCES model_blobs(digest), ref_type TEXT NOT NULL, ref_source TEXT NOT NULL, created_at BIGINT NOT NULL);
CREATE TABLE storage_config (config_key TEXT PRIMARY KEY, config_value TEXT NOT NULL, updated_at BIGINT NOT NULL);
```

### 6.2 Catalog Maintenance & Backups

```bash
# Checkpoint the DuckDB WAL
duckdb /var/lib/k3/catalog.duckdb "CHECKPOINT;"

# Check database size and integrity
duckdb /var/lib/k3/catalog.duckdb "PRAGMA database_size;"

# Export atomic backup to Parquet directory
duckdb /var/lib/k3/catalog.duckdb "EXPORT DATABASE '/var/backups/k3/snapshot-$(date +%Y%m%d)' (FORMAT PARQUET);"
```

---

## 7. Safe Dual-Gate Garbage Collection (`k3-store gc`)

Model deletion unlinks only the alias symlink and manifest; physical blobs are reference-counted in DuckDB. Physical reclamation is executed via `k3-store gc`, protected by a mandatory two-gate safety protocol that works even when `k3-manager` is stopped:

1. **Gate 1 (`flock` Advisory Check)**: Active compute workers hold `flock(LOCK_SH)` on their mapped weight blobs. GC attempts to acquire a non-blocking exclusive lock (`flock(fd, LOCK_EX | LOCK_NB)`). If an engine holds a shared lock, Gate 1 fails and the blob is skipped.
2. **Gate 2 (`/proc/*/maps` Process Scan)**: While holding `LOCK_EX`, GC scans `/proc/*/maps` across all running processes to confirm zero PIDs map the blob's canonical path. If any process maps the blob, Gate 2 fails and the blob is skipped.
3. **TOCTOU Elimination**: GC verifies device and inode identity (`m_fd.dev() == m_path.dev() && m_fd.ino() == m_path.ino()`) immediately before unlinking.

### Operational GC Commands:
```bash
# Preview unreferenced candidates without deleting
k3-store gc --dry-run

# Execute real reclamation sweep
k3-store gc

# Inspect active holders and memory mappings for a specific blob
k3-store who-uses <sha256_digest>
```
