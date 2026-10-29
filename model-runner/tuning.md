# SpacemiT Key Stone K3 Hardware Tuning & Sizing Guide

This guide details the heterogeneous microarchitecture of the SpacemiT Key Stone K3 SoC, core partition masks, KV cache arena sizing formulas, admission queue depth configuration, and dynamic idle core spillover tuning.

---

## 1. Heterogeneous SoC Architecture Overview

The SpacemiT Key Stone K3 SoC integrates 16 heterogeneous 64-bit RISC-V cores (`RV64GCBH`) grouped into two distinct physical clusters with unified 32 GB LPDDR4X memory:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                       SpacemiT Key Stone K3 (16 Cores)                       │
├──────────────────────────────────────┬───────────────────────────────────────┤
│ Cluster 0: X100 General-Purpose Pool │  Cluster 1: A100 AI / Matrix Engine   │
│ Cores: 0 – 7 (Mask: 0x00FF)          │  Cores: 8 – 15 (Mask: 0xFF00)         │
│ Architecture: Out-of-Order (2.15 GHz)│  Architecture: In-Order (1.80 GHz)    │
│ Vector: RVV 1.0 zvl256b (VLEN = 256) │  Vector: RVV 1.0 zvl1024b (VLEN=1024) │
│ Cache: 32K L1, 4 MiB Shared L2       │  Cache: 32K L1, 1 MiB Shared L2       │
│ Matrix: NO XSMTVDotII (traps SIGILL) │  Matrix: XSMTVDotII (8×16 i8 → 8×8 i32)│
│ TCM: None                            │  TCM: 8× 384 KiB Coupled (3.0 MiB)    │
│ Role: Control plane, queues, workers │  Role: High-throughput tensor compute │
└──────────────────────────────────────┴───────────────────────────────────────┘
```

### Architectural Divergence & Critical Constraints:
1. **Cluster 0 (`X100`, Cores `0–7`, `0x00FF`)**: High single-thread clock speed (2.15 GHz) and out-of-order execution make this cluster ideal for non-blocking HTTP parsing, tokenization, chat template evaluation, and scheduling. **It lacks matrix instructions**: executing `smt.vpack.vv` or `smt.vmadot` on cores 0–7 triggers an illegal instruction trap (`SIGILL`).
2. **Cluster 1 (`A100`, Cores `8–15`, `0xFF00`)**: Wide vector registers (`VLEN=1024`, `vlenb=128`) and coupled `XSMTVDotII` matrix acceleration units execute 128 integer operations per cycle per core. Matrix weights must be repacked into `8x16 i8` tiles (`ime_tile_8x16`).

---

## 2. Cluster Partitioning & Core Masks

Model-Runner enforces strict core reservation per ADR-007 and ADR-008:

| Domain | Core Mask | Physical Cores | Purpose | Invariant |
|---|---|---|---|---|
| **Dedicated Active Control** | `0x00C0` | Cores 6, 7 | HTTP/SSE server, prompt tokenization, queue manager | **Strictly forbidden** for compute worker execution |
| **Spare Recovery Watchdog** | `0x0020` | Core 5 | `HealthSupervisor` watchdog, deadline monitor | Bound to watchdog; lendable as spare compute when idle |
| **X100 Compute Cap** | `0x003F` | Cores 0 – 5 | General-purpose compute workers (max 6 threads) | Never overlaps cores 6–7 |
| **A100 Compute Engine** | `0xFF00` | Cores 8 – 15 | AI matrix compute workers (max 8 threads) | Requires `/proc/set_ai_thread` on SpacemiT kernel |

---

## 3. KV Arena Sizing & Memory Capacity Planning

Context memory is pre-allocated in `k3-kv` as isolated, bounded memfd arenas and locked via `mlock`.

### 3.1 Sizing Formula
For a model with $L$ layers, $H_{kv}$ KV heads, head dimension $D$, sequence context $n_{ctx}$, and 16-bit precision (2 bytes per element):

$$\text{KV Arena Bytes} = n_{ctx} \times L \times 2 \times H_{kv} \times D \times 2 \text{ bytes}$$

With paged KV cache block size of 16 tokens (`BLOCK_SIZE_TOKENS = 16`):
$$\text{Block Count} = \left\lceil \frac{n_{ctx}}{16} \right\rceil$$

### 3.2 Sizing Table (Qwen2.5-7B Example: 28 Layers, 4 KV Heads, Head Dim 128)

| Context Window (`n_ctx`) | KV Arena Size | Model Weights (Q4_K_M) | Total Locked RAM | Headroom on 28 GiB Cap |
|---|---|---|---|---|
| **64** (Diagnostic / Test) | `3.5 MiB` | `4.1 GiB` | `4.11 GiB` | `23.89 GiB` safe |
| **2048** (Default Runtime) | `112.0 MiB` | `4.1 GiB` | `4.21 GiB` | `23.79 GiB` safe |
| **4096** | `224.0 MiB` | `4.1 GiB` | `4.32 GiB` | `23.68 GiB` safe |
| **8192** | `448.0 MiB` | `4.1 GiB` | `4.54 GiB` | `23.46 GiB` safe |
| **32768** (Full Context) | `1.79 GiB` | `4.1 GiB` | `5.89 GiB` | `22.11 GiB` safe |

---

## 4. Admission Queue Depth & Streaming Keep-Alive Tuning

Model-Runner implements deep FIFO request queuing (`US-13`, `ADR-015`) to handle traffic bursts without dropping requests:

- **Queue Depth Ceiling (`max_depth`)**: Default `64`. Incoming requests beyond 64 are rejected with HTTP 429 / 529 and `Retry-After: 5`.
- **SSE Keep-Alive Heartbeats**: While waiting in queue, the server emits periodic SSE comments every 2 seconds (`: keep-alive\n\n`) to prevent client timeouts (NAT gateways, reverse proxies, and coding agents).
- **Queue Position Advancements**: Advancing queue position is streamed to clients (`: queue_position=<n>\n\n`).
- **Tuning Guideline**:
  - For interactive coding agents (Cline/Cursor): retain `max_depth = 64` to prevent client request abandonment.
  - For batch processing: increase `max_depth = 256` if clients tolerate multi-minute queue latencies.

---

## 5. Dynamic Idle Core Spillover Tuning

Per ADR-030 and US-11, operators can opt into dynamic idle core lending and borrowing:

```json
{
  "lend_idle_cores": false,
  "borrow_idle_cores": false
}
```

- **Default Behavior (`false`)**: Strict physical core reservation isolation. No core sharing between models.
- **Enabled Behavior (`true`)**:
  - When Model A is idle, its compute cores become available in the lendable pool.
  - When active Model B executes a forward pass, it expands across both its own cores and borrowed cores.
  - **Single-Pass Exclusivity & Immediate Reclaim**: Core expansion is granted strictly for a single forward pass. At the next pass boundary, if Model A receives a prompt, borrowed cores are immediately reclaimed.

---

## 6. Derived Weight Layout Caching & IME Tile Tuning

Weights evaluated on Cluster 1 (`A100`) must be tiled into `8×16` `i8` blocks:

$$\text{Cache Key} = (\text{source\_digest}, \text{recipe\_version}, \text{"ime\_tile\_8x16"})$$

### Retention Policy Options (`retention`):
1. **`keep` (Default)**: Keeps both raw original weights and repacked IME tiles. Recommended when storage capacity is ample (>100 GB). Allows zero-cost auto-rebuilding if runtime recipes change.
2. **`purge_immediate`**: Deletes original raw weights as soon as the derived IME layout is verified and promoted. Saves 50% disk storage. Requires re-downloading if recipe version upgrades.
3. **`purge_after_delay`**: Retains raw weights for a configurable grace period (e.g. 86400 seconds / 24 hours) before marking for garbage collection.
```
