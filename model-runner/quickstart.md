# Model Runner — End-User Quickstart Guide

This guide walks you through setting up, ingesting models into, and querying the **Model Runner** inference solution on native RISC-V hardware (SpacemiT Key Stone K3 SoC) and standard development workstations.

---

## 1. System Overview & Prerequisites

### Architecture Highlights
- **Target Hardware**: SpacemiT Key Stone K3 SoC (16 heterogeneous RISC-V cores):
  - **Cluster 0 (`X100`, cores 0–7, mask `0x00FF`)**: Out-of-Order general-purpose compute cores (`2.15 GHz`, `VLEN=256` / `vlenb=32`). Reserved active control plane runs on cores `6–7` (`0x00C0`), health recovery watchdog on core `5` (`0x0020`), and compute workers on cores `0–5` (capped at max 6 threads, `0x003F`).
  - **Cluster 1 (`A100`, cores 8–15, mask `0xFF00`)**: In-Order matrix/AI cores (`1.80 GHz`, `VLEN=1024` / `vlenb=128`, `XSMTVDotII` matrix instructions).
  - **Memory**: 32 GB unified LPDDR4X RAM with bounded `RLIMIT_MEMLOCK` ceiling (28 GiB max for runtime, preserving 3.3 GiB strictly for Linux kernel and OS services).
- **Daemon Architecture**:
  - `k3-manager`: Control plane orchestration daemon, DuckDB metadata catalog, and out-of-process OpenAI & Anthropic Claude HTTP front-ends.
  - `k3-kv`: Policy-free context memory holder maintaining locked shared memory arenas (`mlock`) surviving worker restarts via Unix Domain Sockets (`SCM_RIGHTS`).
  - `k3-worker`: Cycle-exclusive compute worker process executing forward passes.
  - `k3-store`: Content-addressed storage and dual-gate garbage collection CLI.
  - `k3-diag`: Standalone zero-orchestration diagnostic evaluation and jitter benchmarking CLI.

### Prerequisites
- Linux OS with RISC-V 64-bit support (or macOS/Linux x86_64 for development/mock mode).
- Storage directories created:
  ```bash
  sudo mkdir -p /var/lib/k3/{blobs/sha256,manifests/sha256,models,staging,derived}
  sudo chown -R $USER:$USER /var/lib/k3
  ```
- Environment variable (optional, defaults to `/var/lib/k3`):
  ```bash
  export K3_STORE_ROOT="/var/lib/k3"
  ```

---

## 2. Ingesting Models

Model Runner supports universal ingestion across major formats and sources, deduplicating identical weight bytes via SHA-256 content-addressing.

### Supported Weight Formats
| Format | Extension | Capabilities & Validations |
|---|---|---|
| **GGUF** | `.gguf` | Binary format (v2/v3). Header validated for magic `GGUF` (`0x46554747`), architecture, quantization type, tensor count, and trained context length (`n_ctx`). |
| **SafeTensors** | `.safetensors` | 8-byte LE header size checked, JSON header parsed for tensor shapes, validated against buffer bounds. |
| **OCI / Ollama** | Blobs | OCI manifest layer extraction and format conversion. |
| **Apache Arrow Flight** | Network Stream | IME-tiled tensor stream for distributed multi-node deployment into zero-copy `memfd`. |

### Ingestion Methods

#### A. Ingesting from Hugging Face Hub
Configure credentials via protected secret file (`/etc/k3/credentials/hf.env`, permissions `0600`):
```bash
echo "HF_TOKEN=hf_your_huggingface_token" | sudo tee /etc/k3/credentials/hf.env
sudo chmod 0600 /etc/k3/credentials/hf.env
```

Model acquisition is handled by the isolated source adapter pipeline in `k3-manager` (supporting Hugging Face, Ollama, and local file adapters).

*How it works*:
1. The isolated source adapter streams incoming bytes to `/var/lib/k3/staging/staging_<uuid>.part`.
2. Simultaneously calculates cryptographic SHA-256 digest on the fly.
3. Verifies format headers (GGUF magic `0x46554747` or SafeTensors JSON header).
4. Atomically promotes (`rename()`) the verified artifact into `/var/lib/k3/blobs/sha256/<digest>`.
5. Registers the manifest in DuckDB (`catalog.duckdb`) and creates a human-browsable alias symlink in `/var/lib/k3/models/huggingface/Qwen/Qwen2.5-7B-Instruct/latest`.

#### B. Inspecting and Listing Store Assets (`k3-store`)
The `k3-store` administrative CLI provides verification and inspection across store assets:
```bash
# List registered model aliases
k3-store list aliases

# List canonical model manifests
k3-store list manifests

# List physical content-addressed weight blobs and reference counts
k3-store list blobs
```

#### D. Distributed Multi-Node Provisioning via Apache Arrow Flight
In a multi-board cluster, the control plane host (`k3-manager`) ingests base weights, runs capability filtering, and repacks tensors into hardware-accelerated IME tile layouts. Tensors are streamed to accelerator nodes (`pey-wail-deu`) over Apache Arrow Flight:
```bash
# On target node: k3-rpcbridge receives FlightData into anonymous memfd
# 1. Zero disk writes (protects onboard eMMC flash endurance)
# 2. mlock() locks pages directly in physical RAM
# 3. F_SEAL_WRITE seals the memory segment
# 4. SCM_RIGHTS passes the file descriptor over Unix Domain Socket to k3-worker
```

---

## 3. Verifying Cryptographic Digests and Architecture Recipes

### Inspecting Model Manifests & Aliases
Verify registered models using `k3-store inspect`:
```bash
k3-store inspect local/qwen/qwen2.5-7b/q4km
```
Example Output:
```text
Alias:         local/qwen/qwen2.5-7b/q4km
Manifest Path: /var/lib/k3/manifests/sha256/a8c2f10d...json
Weight Path:   /var/lib/k3/blobs/sha256/b7e9411c...bin
Format:        gguf
Architecture:  qwen2
Recipe:        1.0.0
Quantization:  Q4_K_M
Context Limit: 2048
Weight Digest: b7e9411c...
Size Bytes:    4325881856
```

### Architecture Recipe Capability Filtering
Model Runner enforces strict recipe capability filtering (ADR-023, US-20). The runtime verifies that:
1. The declared architecture (`architecture_id`) and minor algorithmic revision (`recipe_version`) match a compiled kernel recipe in `k3-core`.
2. The tokenizer and chat template definitions in `k3-tokenizer` strictly match the execution recipe.

If an incompatible model or unsupported revision is loaded, Model Runner immediately rejects the load with an explicit error:
```text
[capability_mismatch] unsupported architecture 'unsupported_arch': missing compiled recipe version 1.0.0
```

---

## 4. Running Standalone CLI Evaluation (`k3-diag`)

Before launching background daemons, verify hardware acceleration, memory locking, and token generation using `k3-diag`.

### A. Single-Prompt Standalone Streaming Evaluation
```bash
k3-diag \
  --model /var/lib/k3/blobs/sha256/b7e9411c...bin \
  --prompt "Explain RISC-V RVV 1.0 vector extensions in 2 sentences." \
  --cluster x100 \
  --threads 6 \
  --n-ctx 2048 \
  --max-tokens 64
```
*Expected Result*: The prompt is tokenized in-process, pre-flight memory admission checks RAM, weights are locked via `mlock` and `flock(LOCK_SH)`, and tokens stream to stdout unbuffered in real time.

### B. Multi-Run Jitter & Synchronization Benchmarking
Verify timing consistency and token determinism across repeated iterations ($N \ge 3$):
```bash
k3-diag \
  --model /var/lib/k3/blobs/sha256/b7e9411c...bin \
  --prompt "Sanity check determinism" \
  --coord spin \
  --repeat 5 \
  --summary
```
*Output Summary*:
- Output determinism verified: bit-identical tokens across all runs at temperature 0.
- Mean, Min, Max, and StdDev for TTFT (Time to First Token), decode tokens/sec, and barrier wait overhead.

### C. SpacemiT IME Matrix Acceleration Benchmarking
Benchmark Cluster 1 (`A100`) IME matrix cores vs Cluster 0 (`X100`):
```bash
k3-diag \
  --model /var/lib/k3/blobs/sha256/b7e9411c...bin \
  --cluster both \
  --split phase \
  --ime on \
  --summary
```

### D. Exporting a CostProfile Baseline
Export a machine-readable performance profile for the scheduler:
```bash
k3-diag \
  --model /var/lib/k3/blobs/sha256/b7e9411c...bin \
  --export-profile /etc/k3/profiles/qwen2.5-7b.json
```

---

## 5. Starting the System Services

Start the context holder and control plane manager services:

```bash
# Start the policy-free context memory holder
sudo systemctl start k3-kv.service

# Start the Model Runner daemon service
sudo systemctl start model-runner.service

# Verify service status
sudo systemctl status model-runner.service
```

Verify that the local endpoints are responsive:
```bash
curl -s http://localhost:8080/v1/models | jq .
```
Response:
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
    }
  ]
}
```

---

## 6. Connecting Clients and AI Coding Agents

The `k3-manager` protocol server listens by default on `http://127.0.0.1:8080` (or `0.0.0.0:8080`), exposing standard OpenAI and Anthropic Claude endpoints.

### A. OpenAI Compatible Clients

#### 1. Python (`openai` SDK)
```python
from openai import OpenAI

# Connect to local Model Runner
client = OpenAI(
    base_url="http://localhost:8080/v1",
    api_key="local-token", # any non-empty string
)

# Stream chat completions
response = client.chat.completions.create(
    model="Qwen2.5-7B-Instruct",
    messages=[
        {"role": "system", "content": "You are a concise programming assistant."},
        {"role": "user", "content": "Write a Rust hello world."}
    ],
    temperature=0.0,
    stream=True
)

for chunk in response:
    if chunk.choices and chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end="", flush=True)
print()
```

#### 2. cURL
```bash
curl -N -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer local-token" \
  -d '{
    "model": "Qwen2.5-7B-Instruct",
    "messages": [
      {"role": "user", "content": "Explain asynchronous I/O."}
    ],
    "stream": true
  }'
```

---

### B. Anthropic Claude Compatible Clients

#### 1. Python (`anthropic` SDK)
```python
import anthropic

# Connect to local Model Runner
client = anthropic.Anthropic(
    base_url="http://localhost:8080",
    api_key="local-token",
)

with client.messages.stream(
    model="Qwen2.5-7B-Instruct",
    max_tokens=1024,
    messages=[
        {"role": "user", "content": "How does cgroup v2 isolate memory?"}
    ]
) as stream:
    for text in stream.text_stream:
        print(text, end="", flush=True)
print()
```

#### 2. cURL with Extended Thinking Delta
```bash
curl -N -X POST http://localhost:8080/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: local-token" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "Qwen2.5-7B-Instruct",
    "max_tokens": 1024,
    "thinking": {
      "type": "enabled",
      "budget_tokens": 512
    },
    "messages": [
      {"role": "user", "content": "Prove that the square root of 2 is irrational."}
    ],
    "stream": true
  }'
```

---

### C. AI Coding Agents

#### 1. Cline (VS Code Extension)
1. Open **Cline Settings** in VS Code.
2. Select **API Provider**: `OpenAI Compatible`.
3. Set **Base URL**: `http://localhost:8080/v1`.
4. Set **API Key**: `local`.
5. Set **Model ID**: `Qwen2.5-7B-Instruct`.
6. Set **Context Window**: `2048` (or your model's configured context limit).

#### 2. Cursor
1. Go to **Settings** -> **Models**.
2. Under **OpenAI API Key**, toggle **Override OpenAI Base URL**.
3. Set URL: `http://localhost:8080/v1`.
4. Add Model Name: `Qwen2.5-7B-Instruct`.
5. Select `Qwen2.5-7B-Instruct` as your active chat and editing model.

#### 3. Roo-Code
1. Open Roo-Code provider settings.
2. Select **Anthropic Compatible** or **OpenAI Compatible**.
3. For Anthropic:
   - Base URL: `http://localhost:8080`
   - API Key: `local`
   - Model ID: `Qwen2.5-7B-Instruct`
4. For OpenAI:
   - Base URL: `http://localhost:8080/v1`

#### 4. Continue.dev
Add to your `~/.continue/config.json`:
```json
{
  "models": [
    {
      "title": "K3 Local Model (Qwen 2.5 7B)",
      "provider": "openai",
      "model": "Qwen2.5-7B-Instruct",
      "apiBase": "http://localhost:8080/v1",
      "apiKey": "local"
    }
  ]
}
```

---

## 7. Storage Inspection & Garbage Collection

Inspect active workers and memory holders using `k3-store`:

```bash
# Query active processes mapping a weight blob
k3-store who-uses b7e9411c...

# Reclaim unreferenced blobs with dual-gate safety check
k3-store gc --dry-run
k3-store gc
```

Congratulations! You have successfully ingested, verified, and queried local AI models on native RISC-V hardware with Model Runner. For comprehensive API specifications, configuration schemas, and error mappings, proceed to the [Full Reference Manual](manual.md).
