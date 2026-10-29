# `k3-manager` Architecture & Crate Reference

**Crate**: `k3-manager`  
**Version**: `0.1.0` (Edition 2024, Rust 1.85)  
**Role**: Control plane orchestration daemon, DuckDB CAS catalog, API frontends, admission queues, watchdog supervisor, and `k3-store` CLI  
**Repository**: [`LMA1980/k3-manager`](https://github.com/LMA1980/k3-manager)  
**Rustdoc Reference**:
- [`k3_manager` API Reference](../../api/k3_manager/index.html)
- [`k3_store` API Reference](../../api/k3_store/index.html)

---

## 1. Purpose & System Context

`k3-manager` is the central orchestration and control-plane daemon for Model-Runner. It binds to reserved active control cores 6–7 (`0x00C0`) and handles:
1. **Network APIs**: Exposes OpenAI-compatible (`/v1/models`, `/v1/chat/completions`) and Anthropic Claude-compatible (`/v1/messages`) HTTP/SSE endpoints.
2. **DuckDB CAS Persistence**: Maintains cryptographic content-addressed storage (CAS), model aliases, manifests, token budgets, and single-row session metadata using pure DuckDB (`duckdb`).
3. **Queue Management & Scheduling**: Enforces admission queue ceilings (default: 64 requests), streams SSE keep-alive frames (`: keep-alive`), emits queue positions (`: queue_position=<pos>`), and arbitrates multi-model time-slicing.
4. **Worker Supervision & Isolation**: Moves itself to `/sys/fs/cgroup/k3.slice/control`, creates delegated worker leaves (`.../engines/<model>`), and configures `cpuset.cpus`.
5. **Health Recovery Watchdog**: Runs `HealthSupervisor` pinned to spare recovery core 5 (`0x0020`), detecting worker stalls and preempting runaway workloads with zero downtime.
6. **Storage CLI (`k3-store`)**: Produces the standalone storage administration tool.

---

## 2. Key Public Types & Modules

### 2.1 `ControlPlaneRuntime`
Coordinates active control tasks on cores 6–7 without blocking forward passes:
- Prompt tokenization via `k3-tokenizer`.
- Jinja chat template application.
- Prefix radix block lookup (`PrefixRadixIndex`, 16-token alignment).
- Stop sequence detection.
- Administrative status inspection.

### 2.2 `DuckDbPersistenceStore`
Encapsulates all relational state operations using parameterized prepared statements (zero string interpolation, zero SQL injection vectors):
- Tables: `tenants`, `projects`, `session_last_turns`, `model_blobs`, `model_manifests`, `model_aliases`, `derived_blobs`, `tuning_profiles`, `storage_config`.

### 2.3 `ContentAddressedStore`
Manages immutable SHA-256 blobs and human-readable aliases (`models/<source>/<namespace>/<name>/<tag>`):
- Atomic verification in `staging/` before promotion.
- Strict path component validation against directory traversal (`..`, null bytes).

### 2.4 `HealthSupervisor`
Runs the watchdog loop on core 5 (`0x0020`):
- Monitors heartbeat deadlines (`DEFAULT_HEARTBEAT_TIMEOUT = 5000ms`).
- Monitors forward-pass deadlines (`DEFAULT_PASS_TIMEOUT = 30000ms`).
- Preemption: `SIGTERM` -> 500ms wait -> `SIGKILL` -> reap -> spawn clean replacement worker reattached to `k3-kv` arena.

---

## 3. Protocol Endpoints & HTTP Invariants

- **Header Limit**: 64 KB (`MAX_REQUEST_HEADERS_BYTES = 64 * 1024`). Exceeding returns `HeadersTooLarge`.
- **Body Limit**: 10 MB default (`MAX_REQUEST_BODY_BYTES = 10 * 1024 * 1024`). Exceeding returns HTTP 413 `PayloadTooLarge`.
- **OpenAI `/v1/chat/completions`**:
  - SSE frames: `: keep-alive\n\n`, `: queue_position=<n>\n\n`, `data: { ... }\n\n`, `data: [DONE]\n\n`.
  - Saturation: HTTP 429 Too Many Requests with `Retry-After: 5`.
- **Anthropic Claude `/v1/messages`**:
  - SSE events: `message_start`, `content_block_start`, `content_block_delta` (`thinking_delta`, `text_delta`), `content_block_stop`, `message_delta`, `message_stop`.
  - Saturation: HTTP 529 Overloaded with `Retry-After: 5`.

---

## 4. Storage CLI Binary (`k3-store`)

<a id="storage-cli-binary"></a>
`k3-store` provides command-line storage maintenance independent of the running daemon:

```bash
# Safely reclaim unreferenced blobs via Dual-Gate check
k3-store gc [--dry-run]

# Inspect active flock locks and /proc/*/maps mappings for a blob
k3-store who-uses <sha256_digest>

# List registered assets (blobs, manifests, aliases)
k3-store list [blobs|manifests|aliases]

# Inspect manifest metadata and resolved weight path
k3-store inspect <alias_or_digest>
```

### Dual-Gate Safety Architecture:
1. **Gate 1 (`flock`)**: Checks for shared read lock `flock(LOCK_SH)` held by active compute engines.
2. **Gate 2 (`/proc/*/maps`)**: Scans all running processes to confirm zero PIDs map the blob path into virtual memory.
3. **TOCTOU Guard**: Verifies device and inode match immediately prior to `unlink()`.

---

## 5. Inter-Crate Dependencies

- **Imports**: `k3-core`, `k3-tokenizer`, `duckdb`, `tokio`, `axum`, `serde`, `serde_json`, `libc`, `nix`
- **Consumers**: Top-level service orchestrators and end users
