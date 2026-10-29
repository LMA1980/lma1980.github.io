# Model Runner — Full Reference Manual

This manual provides authoritative reference specifications for the **Model Runner** solution:
1. **[CLI Reference (`k3-store`)](#1-cli-reference-k3-store)**
2. **[Configuration File Schema (`config.toml` & JSON)](#2-configuration-file-schema)**
3. **[OpenAI API Protocol Reference](#3-openai-api-protocol-reference)**
4. **[Anthropic Claude API Protocol Reference](#4-anthropic-claude-api-protocol-reference)**
5. **[Structured Error Handling & Status Code Reference](#5-structured-error-handling--status-code-reference)**

---

## 1. CLI Reference (`k3-store`)

`k3-store` is the administrative command-line utility for managing the Model Runner content-addressed store (CAS), inspecting model builds and manifests, querying active process mappings (`who-uses`), and executing safe dual-gate garbage collection (`gc`) (US-18, US-22, ADR-035, ADR-039, ADR-040).

### Command Syntax
```bash
k3-store [OPTIONS] <COMMAND> [ARGS...]
```

### Global Options
| Option | Environment Variable | Default | Description |
|---|---|---|---|
| `--store-root <PATH>` | `K3_STORE_ROOT` | `/var/lib/k3` | Path to store root directory containing `blobs/`, `manifests/`, `models/`, and `catalog.duckdb`. |
| `--json` | — | `false` | Emits output in machine-readable, formatted JSON. |
| `-h, --help` | — | — | Displays the command help screen and exits. |

---

### Commands

#### A. `who-uses <DIGEST>`
Inspects active shared locks and memory mappings for a specific content digest, determining whether the blob is safe for deletion (US-22 Scenario 3, ADR-040).

- **Arguments**:
  - `<DIGEST>`: 64-character lowercase hexadecimal SHA-256 digest (`^[a-f0-9]{64}$`).
- **Safety Checks**:
  1. **Gate 1 (`flock`)**: Evaluates whether active compute workers hold `flock(LOCK_SH)` on the file.
  2. **Gate 2 (`/proc/*/maps`)**: Scans all active system processes to verify no process memory maps the blob.
- **Example Usage**:
  ```bash
  # Human-readable inspection
  k3-store who-uses b7e9411c52109403a73c1f4e04f981e1136b6f38aa70494cf0785f79a0b98bc9

  # JSON format
  k3-store who-uses b7e9411c... --json
  ```
- **Example Human Output**:
  ```text
  Blob:        b7e9411c52109403a73c1f4e04f981e1136b6f38aa70494cf0785f79a0b98bc9
  Path:        /var/lib/k3/blobs/sha256/b7e9411c52109403a73c1f4e04f981e1136b6f38aa70494cf0785f79a0b98bc9
  Size:        4325881856 bytes
  References:  2 active (["huggingface/Qwen/Qwen2.5-7B/latest", "local/qwen7b/v1"])
  Gate 1 (flock): SHARED LOCK HELD (active worker)
  Gate 2 (mappings): 1 active process mapping(s)
    - PID 14280 (k3-worker) mapped at 0x7fff20000000-0x7fff30000000 (r--p)
  Status:      IN USE (unsafe to delete)
  ```
- **JSON Output Schema**:
  ```json
  {
    "digest": "b7e9411c52109403a73c1f4e04f981e1136b6f38aa70494cf0785f79a0b98bc9",
    "file_path": "/var/lib/k3/blobs/sha256/b7e9411c52109403a73c1f4e04f981e1136b6f38aa70494cf0785f79a0b98bc9",
    "size_bytes": 4325881856,
    "ref_count": 2,
    "referencing_sources": [
      "huggingface/Qwen/Qwen2.5-7B/latest",
      "local/qwen7b/v1"
    ],
    "gate1_shared_lock_held": true,
    "gate2_active_mappings": [
      {
        "pid": 14280,
        "comm": "k3-worker",
        "address_range": "0x7fff20000000-0x7fff30000000",
        "permissions": "r--p",
        "mapped_path": "/var/lib/k3/blobs/sha256/b7e9411c52109403a73c1f4e04f981e1136b6f38aa70494cf0785f79a0b98bc9"
      }
    ]
  }
  ```

---

#### B. `gc [--dry-run]`
Safely reclaims unreferenced or stale weight blobs from storage using mandatory dual-gate checks (US-22, ADR-040).

- **Options**:
  - `--dry-run`: Runs the reclamation sweep and reports eligible candidates and recoverable byte counts without deleting files or altering the catalog.
- **Rules & Invariants**:
  - A blob is candidate for GC only when its catalog `ref_count == 0` or when flagged as an obsolete/stale derived layout (`is_stale == TRUE`).
  - Candidate blobs with active `flock` locks (Gate 1) or `/proc` mappings (Gate 2) are automatically skipped and preserved.
- **Example Usage**:
  ```bash
  # Dry-run sweep
  k3-store gc --dry-run

  # Execute live garbage collection
  k3-store gc
  ```
- **Example Output**:
  ```text
  Garbage Collection Sweep (dry_run: false)
  Candidates examined: 4
  Blobs reclaimed:     2
  Bytes reclaimed:     8651763712 bytes (8.05 GiB)
  Skipped (Gate 1 flock held): ["c4a1..."]
  Skipped (Gate 2 actively mapped): []
  ```

---

#### C. `list [blobs|manifests|aliases]`
Lists registered assets in the DuckDB store catalog.

- **Arguments**:
  - `blobs`: Lists physical blobs stored in `blobs/sha256/` with size and active reference counts.
  - `manifests`: Lists canonical JSON manifests in `manifests/sha256/` with format, architecture, and quantization.
  - `aliases`: Lists human-browsable relative symlinks in `models/`.
  - *(omitted)*: Emits a concise high-level store asset summary.
- **Example Usage**:
  ```bash
  k3-store list aliases
  k3-store list blobs --json
  ```

---

#### D. `inspect <ALIAS_OR_DIGEST>`
Resolves a human-browsable model alias or cryptographic digest, displaying manifest metadata and resolved physical file paths on storage.

- **Arguments**:
  - `<ALIAS_OR_DIGEST>`: E.g., `huggingface/Qwen/Qwen2.5-7B/latest` or a 64-char manifest digest.
- **Example Usage**:
  ```bash
  k3-store inspect huggingface/Qwen/Qwen2.5-7B/latest
  ```

### Model Ingestion & Inactive Alias Unlinking (Manager Architecture)

`k3-store` is dedicated to storage inspection and safe garbage collection. Ingestion, download streaming, and alias registration are handled programmatically through the isolated adapter and staging subsystem in `k3-manager`:

1. **Source Adapters (`SourceAdapter` trait)**:
   - `HuggingFaceAdapter`: Downloads models from Hugging Face Hub with optional bearer token credentials.
   - `OllamaAdapter`: Ingests model blobs and extracts manifests from Ollama libraries.
   - `LocalFileAdapter`: Ingests pre-existing `.gguf` and `.safetensors` files from disk.
2. **Staging & Promotion Pipeline (`StagingPipeline`)**:
   - Downloads stream to temporary staging files in `/var/lib/k3/staging/staging_<uuid>.part`.
   - On-the-fly streaming SHA-256 digest calculation and format header verification (`GGUF` magic `0x46554747` or SafeTensors JSON).
   - Atomic rename (`promote_staged_blob`) into `/var/lib/k3/blobs/sha256/<digest>`.
3. **Manifest & Alias Registration (`ContentAddressedStore`)**:
   - Writes canonical JSON manifest to `/var/lib/k3/manifests/sha256/<manifest_digest>.json`.
   - Records metadata and tracks blob reference counts in DuckDB (`catalog.duckdb`).
   - Creates human-browsable relative symlinks under `/var/lib/k3/models/<source>/<namespace>/<name>/<tag>`.
4. **Alias Unlinking & Reclamation**:
   - Inactive model aliases are unlinked via the CAS API (`ContentAddressedStore::remove_alias`) or DuckDB catalog operations.
   - Unlinking an alias removes the directory symlinks and decrements the blob reference count in DuckDB without immediately deleting the underlying weight file.
   - Orphaned weights are subsequently reclaimed safely using `k3-store gc`.

---

## 2. Configuration File Schema

Model Runner defines its canonical configuration specification in `/etc/k3/config.toml` (or `$K3_CONFIG_PATH`). This specification defines the planned parameters governing storage tiers, control plane core partitioning, HTTP server limits, admission queues, health watchdogs, and multi-tenant resource quotas.

### Annotated `config.toml` Specification

```toml
# ==============================================================================
# Model Runner Configuration File Schema
# ==============================================================================

[store]
# Absolute path to the content-addressed store root (US-18, ADR-036).
# Can reside on primary flash or dedicated secondary NVMe storage.
root_path = "/var/lib/k3"

# Path to the DuckDB relational metadata catalog.
catalog_path = "/var/lib/k3/catalog.duckdb"

# Temporary download staging directory.
staging_dir = "/var/lib/k3/staging"

# High-water mark storage threshold in bytes (e.g., 100 GiB) (US-22 Scenario 2).
# Crossing this emits an operational warning; it never triggers silent automatic deletions.
high_water_mark_bytes = 107374182400

# Original source weight retention policy after derived IME tile layout creation (US-21):
# - "keep": Retains source blob indefinitely (supports automatic offline rebuilds).
# - "purge_immediate": Purges source blob immediately after derived generation.
# - "purge_delayed": Marks source blob for deletion after a configurable grace period.
derived_retention = "keep"


[server]
# TCP socket address and port for the external HTTP protocol frontend (US-23, US-24).
listen_addr = "127.0.0.1:8080"

# Socket read/write timeout in seconds to mitigate Slowloris attacks.
socket_timeout_secs = 30

# Maximum allowed HTTP request body payload in bytes (default: 10 MB).
# Requests exceeding this return HTTP 413 Payload Too Large.
max_request_body_bytes = 10485760

# Maximum allowed HTTP headers section size in bytes (default: 64 KB).
# Requests exceeding this return HTTP 431 Headers Too Large.
max_headers_bytes = 65536


[capacity]
# Cluster 0 (X100) Control Plane Capacity Model (ADR-007, US-06).
# Bitmask for dedicated active control cores (default: cores 6-7 = 0x00C0).
active_control_mask = "0x00C0"

# Bitmask for dedicated spare recovery core (default: core 5 = 0x0020).
# Reserved strictly for HealthSupervisor watchdog preemption and recovery.
spare_recovery_mask = "0x0020"

# Bitmask ceiling for X100 compute workers (default: cores 0-5 = 0x003F).
# Compute threads are capped at max 6 and can never overlap active control cores.
x100_compute_cap_mask = "0x003F"


[queue]
# Per-model admission queue capacity ceiling (US-13, ADR-015).
# Requests arriving when depth reaches this bound return HTTP 429/529 with Retry-After.
max_queue_depth = 32

# Estimated single-pass execution latency in milliseconds for queue wait calculation.
estimated_pass_latency_ms = 100

# Interval in milliseconds for sending streaming SSE keep-alive frames while queued.
keepalive_interval_ms = 1000


[health]
# Health recovery supervisor parameters (US-06.3, ADR-007).
# Heartbeat probe interval for active compute workers in milliseconds.
heartbeat_interval_ms = 1000

# Timeout in milliseconds before a silent worker is declared unresponsive.
heartbeat_timeout_ms = 3000

# Maximum forward pass execution deadline in milliseconds before preemption triggers.
forward_pass_timeout_ms = 30000


# ==============================================================================
# Multi-Tenancy & Project Resource Bounds (ADR-001, ADR-003, US-17)
# ==============================================================================

[tenants.eng]
name = "Engineering Department"

[projects."eng:compiler"]
tenant_id = "eng"
name = "Compiler Development"
# Project token budget limit (u32 integer per AGENTS.md §9).
token_budget = 5000000

[projects."eng:runtime"]
tenant_id = "eng"
name = "Runtime Engine"
token_budget = 20000000


# ==============================================================================
# Per-Model Execution & Tuning Profiles (ADR-014, ADR-027, ADR-030, ADR-031)
# ==============================================================================

[models."Qwen2.5-7B-Instruct"]
# Target compute cluster: "x100", "a100", or "both".
cluster = "x100"
# Cores allocated on Cluster 0 (max 6, within 0x003F).
x100_cores = 6
# Cores allocated on Cluster 1 (0-8 cores).
a100_cores = 0
# Scheduling priority class: "throughput" or "latency" (ADR-014).
priority_class = "throughput"
# Context window sequence length bound in tokens (ADR-027).
n_ctx = 2048
# Opt-in dynamic idle core spillover permissions (ADR-030).
lend_idle_cores = false
borrow_idle_cores = false
```

---

## 3. OpenAI API Protocol Reference

The OpenAI-compatible adapter exposes drop-in endpoints for standard SDKs, coding tools, and applications (US-23, ADR-015, ADR-020, ADR-027, ADR-031).

### `GET /v1/models`
Retrieves all loaded models in the runtime, explicitly surfacing unprofiled conservative default statuses and actionable tuning advisories (ADR-031).

- **HTTP Request**:
  ```http
  GET /v1/models HTTP/1.1
  Host: localhost:8080
  ```
- **HTTP Response** (`200 OK`):
  ```json
  {
    "object": "list",
    "data": [
      {
        "id": "Qwen2.5-7B-Instruct",
        "object": "model",
        "created": 1700000000,
        "owned_by": "k3",
        "unprofiled": true,
        "profile_status": "unprofiled",
        "priority_class": "throughput",
        "cluster": "x100",
        "a100_cores": 0,
        "n_ctx": 2048,
        "lend_idle_cores": false,
        "borrow_idle_cores": false,
        "advisory_notice": "Model is running with safe conservative defaults (unprofiled). Run 'k3-diag' to profile hardware performance and apply an operator tuning profile."
      },
      {
        "id": "synthetic-model-1",
        "object": "model",
        "created": 1700000000,
        "owned_by": "k3",
        "unprofiled": false,
        "profile_status": "profiled",
        "priority_class": "latency",
        "cluster": "both",
        "a100_cores": 8,
        "n_ctx": 8192,
        "lend_idle_cores": true,
        "borrow_idle_cores": true
      }
    ]
  }
  ```

---

### `POST /v1/chat/completions`
Dispatches chat completions supporting synchronous JSON, Server-Sent Events (SSE) streaming with live queue feedback, transparent tool calling pass-through, and protocol-native error handling.

- **Request Headers**:
  - `Content-Type: application/json`
  - `Authorization: Bearer <TOKEN>` *(optional for local loopback)*
- **Request Parameters**:
  | Field | Type | Required | Description |
  |---|---|---|---|
  | `model` | string | Yes | Logical identifier of the loaded target model. |
  | `messages` | array | Yes | Array of message objects (`role`, `content`, optional `tool_calls`, `tool_call_id`). |
  | `stream` | boolean | No | When `true`, streams Server-Sent Events chunks (`Transfer-Encoding: chunked`). |
  | `temperature` | number | No | Sampling temperature (0.0 for deterministic greedy argmax). |
  | `max_tokens` | integer | No | Maximum generation token ceiling. |
  | `tools` | array | No | Pass-through tool specifications with JSON Schema function signatures. |
  | `tool_choice` | string/object | No | Tool selection directive (`auto`, `none`, or explicit function object). |

#### Streaming SSE Framing Protocol
When `stream: true`, the connection transitions to chunked SSE streaming (`text/event-stream`).

1. **Queue Feedback & Keep-Alive Comments**:
   While waiting in the model's admission queue, the frontend emits periodic SSE comments every `keepalive_interval_ms` (1000ms):
   ```http
   : keep-alive

   : queue_position=2

   : queue-position 2

   ```
2. **Initial Assistant Role Frame**:
   ```http
   data: {"id":"chatcmpl-1a2b3c","object":"chat.completion.chunk","created":1700000000,"model":"Qwen2.5-7B-Instruct","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}

   ```
3. **Incremental Content Token Chunks**:
   ```http
   data: {"id":"chatcmpl-1a2b3c","object":"chat.completion.chunk","created":1700000000,"model":"Qwen2.5-7B-Instruct","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}

   data: {"id":"chatcmpl-1a2b3c","object":"chat.completion.chunk","created":1700000000,"model":"Qwen2.5-7B-Instruct","choices":[{"index":0,"delta":{"content":" world"},"finish_reason":null}]}

   ```
4. **Transparent Tool Call Pass-Through**:
   If the model emits a tool call invocation:
   ```http
   data: {"id":"chatcmpl-1a2b3c","object":"chat.completion.chunk","created":1700000000,"model":"Qwen2.5-7B-Instruct","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_calc_987","type":"function","function":{"name":"calculate_hash","arguments":"{\"input\": \"test\"}"}}]},"finish_reason":null}]}

   data: {"id":"chatcmpl-1a2b3c","object":"chat.completion.chunk","created":1700000000,"model":"Qwen2.5-7B-Instruct","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

   ```
5. **Stream Termination**:
   ```http
   data: [DONE]

   ```

---

## 4. Anthropic Claude API Protocol Reference

The Anthropic Claude adapter provides native compatibility with Claude-oriented developer tools, coding agents, and SDKs (US-24, ADR-015, ADR-020, ADR-027).

### `POST /v1/messages`
Processes messages requests according to Anthropic protocol specifications, including multi-part content blocks, system prompts, extended thinking deltas, and tool use blocks.

- **Request Headers**:
  - `Content-Type: application/json`
  - `x-api-key: <TOKEN>` or `Authorization: Bearer <TOKEN>`
  - `anthropic-version: 2023-06-01`
- **Request Parameters**:
  | Field | Type | Required | Description |
  |---|---|---|---|
  | `model` | string | Yes | Logical model identifier. |
  | `messages` | array | Yes | Array of messages. **Invariants**: Array cannot be empty, must begin with role `user`, and roles must strictly alternate (`user` -> `assistant` -> `user`). |
  | `max_tokens` | integer | Yes | Maximum output tokens. Must be an integer greater than 0. |
  | `system` | string/array | No | Top-level system prompt instructions. |
  | `stream` | boolean | No | When `true`, emits Anthropic SSE lifecycle events. |
  | `thinking` | object | No | Extended thinking configuration: `{"type": "enabled", "budget_tokens": 1024}`. |
  | `tools` | array | No | Tool definitions schemas (`name`, `description`, `input_schema`). |

#### Claude Streaming Event Lifecycle
When `stream: true`, the adapter emits the complete sequence of Anthropic protocol events:

1. **Queue Feedback & Keep-Alive**:
   ```http
   : keep-alive

   : queue-position 2

   ```
2. **`message_start`**:
   ```http
   event: message_start
   data: {"type":"message_start","message":{"id":"msg_1001","type":"message","role":"assistant","content":[],"model":"Qwen2.5-7B-Instruct","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":18,"output_tokens":1}}}

   ```
3. **Thinking Block Start & Deltas** *(when `thinking.type == "enabled"`)*:
   ```http
   event: content_block_start
   data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}

   event: content_block_delta
   data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Analyzing problem constraints..."}}

   event: content_block_stop
   data: {"type":"content_block_stop","index":0}

   ```
4. **Text Block Start & Deltas**:
   ```http
   event: content_block_start
   data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

   event: content_block_delta
   data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Here is the solution:"}}

   event: content_block_stop
   data: {"type":"content_block_stop","index":1}

   ```
5. **Tool Use Block** *(when model triggers tool calling)*:
   ```http
   event: content_block_start
   data: {"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"toolu_9876","name":"get_weather","input":{}}}

   event: content_block_delta
   data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\"location\": \"Berlin\"}"}}

   event: content_block_stop
   data: {"type":"content_block_stop","index":2}

   ```
6. **`message_delta` & `message_stop`**:
   ```http
   event: message_delta
   data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":42}}

   event: message_stop
   data: {"type":"message_stop"}

   ```

---

## 5. Structured Error Handling & Status Code Reference

Model Runner translates internal system errors (`K3Error`, `ManagerError`, `ServerError`) into deterministic HTTP status codes and protocol-specific payload structures.

### Error Mapping Matrix
| Domain Error / Invariant | CLI Exit Code | HTTP Status | OpenAI Error Response | Claude Error Response | Headers Emitted |
|---|---|---|---|---|---|
| **`QueueSaturated`** | 23 | **429** (OpenAI)<br>**529** (Claude) | `code: "rate_limit_exceeded"`<br>`type: "requests"` | `error.type: "overloaded_error"` | `Retry-After: <secs>` |
| **`ContextLengthExceeded`** | 12 | **400** Bad Request | `code: "context_length_exceeded"`<br>`type: "invalid_request_error"` | `error.type: "invalid_request_error"` | — |
| **`CapabilityMismatch`** | 10 | **400** Bad Request | `code: "capability_mismatch"`<br>`type: "invalid_request_error"` | `error.type: "invalid_request_error"` | — |
| **`AffinityError`** | 13 | **400** Bad Request | `code: "affinity_error"`<br>`type: "invalid_request_error"` | `error.type: "invalid_request_error"` | — |
| **`PayloadTooLarge`** (>10MB) | — | **413** Payload Too Large | `code: "payload_too_large"`<br>`type: "invalid_request_error"` | `error.type: "invalid_request_error"` | — |
| **`HeadersTooLarge`** (>64KB) | — | **431** Request Header Too Large | `code: "headers_too_large"` | `error.type: "invalid_request_error"` | — |
| **`ModelNotFound`** | — | **404** Not Found | `code: "model_not_found"` | `error.type: "not_found_error"` | — |
| **`PriorityOverrideRejected`** | — | **400** Bad Request | `code: "priority_override_rejected"` | `error.type: "invalid_request_error"` | — |
| **`ConcurrencyLimitExceeded`** | — | **503** Service Unavailable | `code: "concurrency_limit_exceeded"` | `error.type: "overloaded_error"` | — |
| **`WorkerUnresponsive`** (timeout) | — | **504** Gateway Timeout | `code: "worker_unresponsive"` | `error.type: "timeout_error"` | — |
| **`InsufficientLockableMemory`** | 11 | **503** Service Unavailable | `code: "insufficient_memory"` | `error.type: "overloaded_error"` | — |

---

### Structured Error Examples

#### OpenAI Format (HTTP 429 Queue Saturated)
```http
HTTP/1.1 429 Too Many Requests
Content-Type: application/json
Retry-After: 5

{
  "error": {
    "message": "Model admission queue saturated (32/32)",
    "type": "requests",
    "param": null,
    "code": "rate_limit_exceeded"
  }
}
```

#### Claude Format (HTTP 529 Overloaded Error)
```http
HTTP/1.1 529 Overloaded
Content-Type: application/json
Retry-After: 5

{
  "type": "error",
  "error": {
    "type": "overloaded_error",
    "message": "Model admission queue is saturated (32/32)"
  }
}
```

#### Context Length Exceeded (HTTP 400 Bad Request)
```http
HTTP/1.1 400 Bad Request
Content-Type: application/json

{
  "error": {
    "message": "Prompt tokens (2150) exceed model context window limit of 2048 tokens",
    "type": "invalid_request_error",
    "param": "messages",
    "code": "context_length_exceeded"
  }
}
```

---

## 6. Architecture & System Decision Cross-References

| Area | Key System Invariants & ADRs |
|---|---|
| **Content Store** | [ADR-035](https://github.com/LMA1980/model-runner/blob/main/decisions/ADR-035-store-layout.md) (CAS layout), [ADR-036](https://github.com/LMA1980/model-runner/blob/main/decisions/ADR-036-store-location.md) (Secondary storage tiers), [ADR-040](https://github.com/LMA1980/model-runner/blob/main/decisions/ADR-040-gc-safety.md) (Dual-gate GC checks) |
| **Hardware Affinity** | [ADR-007](https://github.com/LMA1980/model-runner/blob/main/decisions/ADR-007-control-plane-cores.md) (X100 6-7 control, 5 recovery), [ADR-008](https://github.com/LMA1980/model-runner/blob/main/decisions/ADR-008-core-partitioning.md) (Cgroup cpuset isolation), [ADR-041](https://github.com/LMA1980/model-runner/blob/main/decisions/ADR-041-isolation-domains.md) (Process isolation) |
| **Execution & Queues**| [ADR-014](https://github.com/LMA1980/model-runner/blob/main/decisions/ADR-014-priority.md) (Operator priority classes), [ADR-015](https://github.com/LMA1980/model-runner/blob/main/decisions/ADR-015-admission-queue.md) (Patient admission queues), [ADR-027](https://github.com/LMA1980/model-runner/blob/main/decisions/ADR-027-context-window.md) (Context bounds) |
| **Model Lifecycle** | [ADR-023](https://github.com/LMA1980/model-runner/blob/main/decisions/ADR-023-architecture-onboarding.md) (Capability filters), [ADR-028](https://github.com/LMA1980/model-runner/blob/main/decisions/ADR-028-a100-premise.md) & [ADR-031](https://github.com/LMA1980/model-runner/blob/main/decisions/ADR-031-unprofiled-models.md) (Safe unprofiled defaults), [ADR-038](https://github.com/LMA1980/model-runner/blob/main/decisions/ADR-038-derived-weights.md) (IME derived layouts) |
