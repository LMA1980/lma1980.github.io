# SpacemiT K3 5-Way AI Runtime Comparative Benchmark & Support Matrix

Live empirical comparative benchmark evaluating **five AI inference runtimes** across **all 52 planned Milestone 4 models** (including both implemented recipes and planned architectures not yet implemented) on a dedicated **SpacemiT Key Stone K3 (`riscv64`, `worker-riscv64`)** reference board.

> **Live Campaign Status (`2026-11-10 22:59 UTC`)**: **`0 / 52`** planned models evaluated and published live. Remaining queued waves stream to this page immediately upon completion.

## 1. Five Evaluated Runtimes & Dedicated Hardware Isolation

During benchmarking, the **SpacemiT K3 Reference Board (`worker-riscv64`)** is strictly dedicated to sequential single-model, single-runtime execution: all CI/CD workers (`MuCI`, `MuCD`) and background inference services are placed on hold, leaving only core Linux kernel tasks and the lightweight `MuObserve` edge collector (`< 5 MiB` RAM) active to catalogue telemetry. **All 16 physical cores (`0–15`, `0xFFFF`)** — 8× `X100` Out-of-Order cores (`2.15 GHz`, `VLEN = 256`) and 8× `A100` In-Order AI/Matrix cores (`1.80 GHz`, `VLEN = 1024` + `XSMTVDotII` `8×16` `int8` matrix engine) — and **32 GiB LPDDR5** (`28 GiB` bounded `RLIMIT_MEMLOCK` ceiling) are available to each runtime.

|   #   | Solution / Baseline                            | Build Provenance & Kernel Backend                                       | 16-Core Scheduling & Memory Policy                                                                                  | Models Supported So Far |
| :---: | :--------------------------------------------- | :---------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------ | :---------------------: |
| **1** | **Baseline 1: `ollama` (SpacemiT patches)**    | `spacemit-ollama-toolkit 0.0.13 (+spacemit, CPU_RISCV64_SPACEMIT IME2)` | `num_thread=16` (`CPU_RISCV64_SPACEMIT` `IME2` on `A100` `0xFF00` + control on `X100`)                              |       **`0 / 0`**       |
| **2** | **Baseline 2: `ollama` (`latest git`)**        | `upstream ollama/ollama main HEAD (native riscv64 RVV 1.0)`             | `num_thread=16` across all 16 RVV 1.0 cores (`0xFFFF`), zero SpacemiT patches                                       |       **`0 / 0`**       |
| **3** | **Baseline 3: `llama.cpp` (SpacemiT patches)** | `0.6.0-dev build 11552 (23b0202a1, CPU_RISCV64_SPACEMIT IME2)`          | `-t 16` (`CPU_RISCV64_SPACEMIT` `use_ime2=1`, `A100` `0xFF00` preferred matrix pool)                                |       **`0 / 0`**       |
| **4** | **Baseline 4: `llama.cpp` (`latest git`)**     | `upstream ggerganov/llama.cpp master HEAD (static RVV 1.0)`             | `-t 16` static RVV 1.0 (`-DGGML_RVV=ON -DBUILD_SHARED_LIBS=OFF`) across `0xFFFF`                                    |       **`0 / 0`**       |
| **5** | **Solution 5: `jero-engine` (`jero-diag`)**    | `jero-engine 0.1.0 (jero-diag, RVV 1.0 + A100 XSMTVDotII IME)`          | `mlock` + `flock` bounded `28 GiB` admission, `A100` `0xFF00` (`8t`) & `0xFFFF` (`16t` `X100+A100` row-split `IME`) |       **`0 / 0`**       |

______________________________________________________________________

## 2. Master 5-Way Support, Throughput & Capability Summary Matrix

Each cell reports **Support Status**, **Mean Decode Throughput (`tok/s`)**, **Mean Prefill Throughput (`tok/s`)**, and **5-Pillar Open-Source Composite Accuracy (`%`)** evaluated on the exact same byte-for-byte GGUF checkpoint at greedy temperature `0.0`:

| Model (`Wave`)                                        | Family & Milestone Epic                                             | Arch / Quant (`Size`)        | `jero-engine` Roadmap Status                      | 1. `ollama` (SpacemiT) | 2. `ollama` (`git`)  | 3. `llama.cpp` (SpacemiT) | 4. `llama.cpp` (`git`) | 5. `jero-engine`     |
| :---------------------------------------------------- | :------------------------------------------------------------------ | :--------------------------- | :------------------------------------------------ | :--------------------- | :------------------- | :------------------------ | :--------------------- | :------------------- |
| **Qwen2.5-0.5B-Instruct** (`W1`)                      | Alibaba Qwen 2.5 (`jero-engine#10 / #33`)                           | `qwen2` · `Q4_K_M` (—)       | Implemented (`jero-arch-llama` `qwen2`)           | ⏳ `Queued (Wave 1)`   | ⏳ `Queued (Wave 1)` | ⏳ `Queued (Wave 1)`      | ⏳ `Queued (Wave 1)`   | ⏳ `Queued (Wave 1)` |
| **Qwen2.5-Coder-0.5B-Instruct** (`W1`)                | Alibaba Qwen 2.5 (`jero-engine#10 / #33`)                           | `qwen2` · `Q8_0` (—)         | Implemented (`jero-arch-llama` `qwen2`)           | ⏳ `Queued (Wave 1)`   | ⏳ `Queued (Wave 1)` | ⏳ `Queued (Wave 1)`      | ⏳ `Queued (Wave 1)`   | ⏳ `Queued (Wave 1)` |
| **Qwen3-0.6B** (`W1`)                                 | Alibaba Qwen 3 (`jero-engine#33`)                                   | `qwen3` · `Q4_K_M` (—)       | Planned (`qwen3` QK-Norm)                         | ⏳ `Queued (Wave 1)`   | ⏳ `Queued (Wave 1)` | ⏳ `Queued (Wave 1)`      | ⏳ `Queued (Wave 1)`   | ⏳ `Queued (Wave 1)` |
| **LiquidAI LFM2.5-Thinking-1.2B** (`W1`)              | LiquidAI LFM2 Hybrid (`jero-engine#56`)                             | `lfm2` · `Q4_K_M` (—)        | Planned (`lfm2` Short-Conv + GQA)                 | ⏳ `Queued (Wave 1)`   | ⏳ `Queued (Wave 1)` | ⏳ `Queued (Wave 1)`      | ⏳ `Queued (Wave 1)`   | ⏳ `Queued (Wave 1)` |
| **TEv1-0.8B Decision SLM** (`W1`)                     | Decision & Routing SLMs (`jero-engine#46`)                          | `qwen3` · `Q8_0` (—)         | Planned (Decision/Routing SLM)                    | ⏳ `Queued (Wave 1)`   | ⏳ `Queued (Wave 1)` | ⏳ `Queued (Wave 1)`      | ⏳ `Queued (Wave 1)`   | ⏳ `Queued (Wave 1)` |
| **Gemma-3-1B-IT** (`W1`)                              | Google Gemma 3 (`jero-engine#22`)                                   | `gemma3` · `Q4_K_M` (—)      | Planned (`gemma3` 5:1 Hybrid SWA)                 | ⏳ `Queued (Wave 1)`   | ⏳ `Queued (Wave 1)` | ⏳ `Queued (Wave 1)`      | ⏳ `Queued (Wave 1)`   | ⏳ `Queued (Wave 1)` |
| **Qwen2.5-Coder-1.5B-Instruct** (`W1`)                | Alibaba Qwen 2.5 (`jero-engine#10 / #33`)                           | `qwen2` · `Q4_K_M` (—)       | Implemented (`jero-arch-llama` `qwen2`)           | ⏳ `Queued (Wave 1)`   | ⏳ `Queued (Wave 1)` | ⏳ `Queued (Wave 1)`      | ⏳ `Queued (Wave 1)`   | ⏳ `Queued (Wave 1)` |
| **Llama-4-Scout-17B-16E (109B)** (`W1`)               | Meta Llama 4 (`jero-engine#10`)                                     | `llama4` · `Q4_K_M` (—)      | Implemented (`jero-arch-llama` `llama4` iRoPE)    | ⏳ `Queued (Wave 1)`   | ⏳ `Queued (Wave 1)` | ⏳ `Queued (Wave 1)`      | ⏳ `Queued (Wave 1)`   | ⏳ `Queued (Wave 1)` |
| **Meta Prompt-Guard-86M (DeBERTa-v3)** (`W1`)         | Security & Guardrails (`jero-manager#31`)                           | `deberta-v3` · `F16` (—)     | Planned (`deberta-v3` Bidirectional Encoder)      | ⏳ `Queued (Wave 1)`   | ⏳ `Queued (Wave 1)` | ⏳ `Queued (Wave 1)`      | ⏳ `Queued (Wave 1)`   | ⏳ `Queued (Wave 1)` |
| **IBM Granite-TinyTimeMixers-R2** (`W1`)              | Machine-Models (Time-Series) (`jero-manager#43`)                    | `tinytimemixer` · `F32` (—)  | Planned (Numerical SafeTensors Bridge)            | ⏳ `Queued (Wave 1)`   | ⏳ `Queued (Wave 1)` | ⏳ `Queued (Wave 1)`      | ⏳ `Queued (Wave 1)`   | ⏳ `Queued (Wave 1)` |
| **Prior-Labs TabPFN-v2** (`W1`)                       | Machine-Models (Tabular ICL) (`jero-manager#43`)                    | `tabpfn-v2` · `F32` (—)      | Planned (2D Tabular Attention Bridge)             | ⏳ `Queued (Wave 1)`   | ⏳ `Queued (Wave 1)` | ⏳ `Queued (Wave 1)`      | ⏳ `Queued (Wave 1)`   | ⏳ `Queued (Wave 1)` |
| **Llama-3.2-1B-Instruct** (`W2`)                      | Meta Llama 3.2 (`jero-engine#10`)                                   | `llama` · `Q8_0` (—)         | Implemented (`jero-arch-llama`)                   | ⏳ `Queued (Wave 2)`   | ⏳ `Queued (Wave 2)` | ⏳ `Queued (Wave 2)`      | ⏳ `Queued (Wave 2)`   | ⏳ `Queued (Wave 2)` |
| **DeepSeek-R1-Distill-Qwen-1.5B** (`W2`)              | DeepSeek Reasoning (`jero-engine#33`)                               | `qwen2` · `Q4_K_M` (—)       | Implemented (`jero-arch-llama` `qwen2`)           | ⏳ `Queued (Wave 2)`   | ⏳ `Queued (Wave 2)` | ⏳ `Queued (Wave 2)`      | ⏳ `Queued (Wave 2)`   | ⏳ `Queued (Wave 2)` |
| **Llama-Guard-3-1B** (`W2`)                           | Security & Guardrails (`jero-manager#31`)                           | `llama` · `Q8_0` (—)         | Implemented Arch / Planned Guardrail Policy       | ⏳ `Queued (Wave 2)`   | ⏳ `Queued (Wave 2)` | ⏳ `Queued (Wave 2)`      | ⏳ `Queued (Wave 2)`   | ⏳ `Queued (Wave 2)` |
| **Gemma-2-2B-IT** (`W2`)                              | Google Gemma 2 (`jero-engine#22`)                                   | `gemma2` · `Q4_0` (—)        | Planned (`gemma2` Softcapping + SWA)              | ⏳ `Queued (Wave 2)`   | ⏳ `Queued (Wave 2)` | ⏳ `Queued (Wave 2)`      | ⏳ `Queued (Wave 2)`   | ⏳ `Queued (Wave 2)` |
| **ShieldGemma-2B** (`W2`)                             | Security & Guardrails (`jero-manager#31`)                           | `gemma2` · `Q4_0` (—)        | Planned (`gemma2` Safety Classifier)              | ⏳ `Queued (Wave 2)`   | ⏳ `Queued (Wave 2)` | ⏳ `Queued (Wave 2)`      | ⏳ `Queued (Wave 2)`   | ⏳ `Queued (Wave 2)` |
| **BitNet-b1.58-2B-4T (`i2_s`)** (`W2`)                | Microsoft BitNet 1.58-bit (`jero-kernels-rvv#10`)                   | `bitnet-b1.58` · `i2_s` (—)  | Implemented Recipe (`i2_s` Rejected per ADR-023)  | ⏳ `Queued (Wave 2)`   | ⏳ `Queued (Wave 2)` | ⏳ `Queued (Wave 2)`      | ⏳ `Queued (Wave 2)`   | ⏳ `Queued (Wave 2)` |
| **BitNet-b1.58-2B-4T (`TQ2_0`)** (`W2`)               | Microsoft BitNet 1.58-bit (`jero-kernels-rvv#10`)                   | `bitnet-b1.58` · `TQ2_0` (—) | Implemented (`jero-arch-bitnet` `TQ2_0`)          | ⏳ `Queued (Wave 2)`   | ⏳ `Queued (Wave 2)` | ⏳ `Queued (Wave 2)`      | ⏳ `Queued (Wave 2)`   | ⏳ `Queued (Wave 2)` |
| **RWKV-7-World-1.5B (`Q8_0`)** (`W2`)                 | Linear-Time Recurrent (RWKV-7) (`jero-engine#56`)                   | `rwkv7` · `Q8_0` (—)         | Planned (`rwkv7` Generalized Delta Rule)          | ⏳ `Queued (Wave 2)`   | ⏳ `Queued (Wave 2)` | ⏳ `Queued (Wave 2)`      | ⏳ `Queued (Wave 2)`   | ⏳ `Queued (Wave 2)` |
| **Mamba-2.8B-HF (`Q8_0`)** (`W3`)                     | Linear-Time SSM (Mamba) (`jero-engine#56`)                          | `mamba` · `Q8_0` (—)         | Planned (`mamba` / `mamba2` Selective SSM)        | ⏳ `Queued (Wave 3)`   | ⏳ `Queued (Wave 3)` | ⏳ `Queued (Wave 3)`      | ⏳ `Queued (Wave 3)`   | ⏳ `Queued (Wave 3)` |
| **Qwen2.5-Coder-3B-Instruct** (`W3`)                  | Alibaba Qwen 2.5 (`jero-engine#10 / #33`)                           | `qwen2` · `Q4_K_M` (—)       | Implemented (`jero-arch-llama` `qwen2`)           | ⏳ `Queued (Wave 3)`   | ⏳ `Queued (Wave 3)` | ⏳ `Queued (Wave 3)`      | ⏳ `Queued (Wave 3)`   | ⏳ `Queued (Wave 3)` |
| **Llama-3.2-3B-Instruct** (`W3`)                      | Meta Llama 3.2 (`jero-engine#10`)                                   | `llama` · `Q4_K_M` (—)       | Implemented (`jero-arch-llama`)                   | ⏳ `Queued (Wave 3)`   | ⏳ `Queued (Wave 3)` | ⏳ `Queued (Wave 3)`      | ⏳ `Queued (Wave 3)`   | ⏳ `Queued (Wave 3)` |
| **Phi-3.5-mini-instruct (3.8B)** (`W3`)               | Microsoft Phi-3 (`jero-engine#10`)                                  | `phi3` · `Q4_0` (—)          | Implemented (`jero-arch-phi3`)                    | ⏳ `Queued (Wave 3)`   | ⏳ `Queued (Wave 3)` | ⏳ `Queued (Wave 3)`      | ⏳ `Queued (Wave 3)`   | ⏳ `Queued (Wave 3)` |
| **Phi-4-mini-instruct (3.8B)** (`W3`)                 | Microsoft Phi-4 (`jero-engine#10`)                                  | `phi3` · `Q4_K_M` (—)        | Implemented (`jero-arch-phi3` `phi4`)             | ⏳ `Queued (Wave 3)`   | ⏳ `Queued (Wave 3)` | ⏳ `Queued (Wave 3)`      | ⏳ `Queued (Wave 3)`   | ⏳ `Queued (Wave 3)` |
| **Gemma-3-4B-IT** (`W3`)                              | Google Gemma 3 (`jero-engine#22`)                                   | `gemma3` · `Q4_K_M` (—)      | Planned (`gemma3` 5:1 Hybrid SWA)                 | ⏳ `Queued (Wave 3)`   | ⏳ `Queued (Wave 3)` | ⏳ `Queued (Wave 3)`      | ⏳ `Queued (Wave 3)`   | ⏳ `Queued (Wave 3)` |
| **Qwen3-4B** (`W3`)                                   | Alibaba Qwen 3 (`jero-engine#33`)                                   | `qwen3` · `Q4_K_M` (—)       | Planned (`qwen3` QK-Norm)                         | ⏳ `Queued (Wave 3)`   | ⏳ `Queued (Wave 3)` | ⏳ `Queued (Wave 3)`      | ⏳ `Queued (Wave 3)`   | ⏳ `Queued (Wave 3)` |
| **NVIDIA Nemotron-Labs Dory1.0-4B (`Q5_K_M`)** (`W3`) | NVIDIA Dory Looped-Recurrent (`jero-engine#81`)                     | `dory` · `Q5_K_M` (—)        | Implemented (`jero-arch-dory`)                    | ⏳ `Queued (Wave 3)`   | ⏳ `Queued (Wave 3)` | ⏳ `Queued (Wave 3)`      | ⏳ `Queued (Wave 3)`   | ⏳ `Queued (Wave 3)` |
| **TEv1-4B Decision SLM** (`W4`)                       | Decision & Routing SLMs (`jero-engine#46`)                          | `qwen3` · `Q4_K_M` (—)       | Planned (Decision/Routing SLM)                    | ⏳ `Queued (Wave 4)`   | ⏳ `Queued (Wave 4)` | ⏳ `Queued (Wave 4)`      | ⏳ `Queued (Wave 4)`   | ⏳ `Queued (Wave 4)` |
| **LiquidAI LFM2.5-MoE** (`W4`)                        | LiquidAI LFM2 Hybrid (`jero-engine#56`)                             | `lfm2moe` · `Q4_K_M` (—)     | Planned (`lfm2moe` Short-Conv + MoE)              | ⏳ `Queued (Wave 4)`   | ⏳ `Queued (Wave 4)` | ⏳ `Queued (Wave 4)`      | ⏳ `Queued (Wave 4)`   | ⏳ `Queued (Wave 4)` |
| **Gemma-4-E4B-IT** (`W4`)                             | Google Gemma 4 (`jero-engine#22`)                                   | `gemma4` · `Q4_K_M` (—)      | Planned (`gemma4` Hybrid KV Sharing)              | ⏳ `Queued (Wave 4)`   | ⏳ `Queued (Wave 4)` | ⏳ `Queued (Wave 4)`      | ⏳ `Queued (Wave 4)`   | ⏳ `Queued (Wave 4)` |
| **Qwen2.5-Coder-7B-Instruct** (`W4`)                  | Alibaba Qwen 2.5 (`jero-engine#10 / #33`)                           | `qwen2` · `Q4_K_M` (—)       | Implemented (`jero-arch-llama` `qwen2`)           | ⏳ `Queued (Wave 4)`   | ⏳ `Queued (Wave 4)` | ⏳ `Queued (Wave 4)`      | ⏳ `Queued (Wave 4)`   | ⏳ `Queued (Wave 4)` |
| **Mistral-7B-Instruct-v0.3** (`W4`)                   | Mistral Dense (`jero-engine#10`)                                    | `mistral` · `Q4_0` (—)       | Implemented (`jero-arch-mistral`)                 | ⏳ `Queued (Wave 4)`   | ⏳ `Queued (Wave 4)` | ⏳ `Queued (Wave 4)`      | ⏳ `Queued (Wave 4)`   | ⏳ `Queued (Wave 4)` |
| **IBM Granite-4.1-Guardian-8B** (`W5`)                | Security & Guardrails / Hybrid (`jero-manager#31 / jero-engine#56`) | `granite` · `Q4_K_M` (—)     | Planned (`granite` Guardrail)                     | ⏳ `Queued (Wave 5)`   | ⏳ `Queued (Wave 5)` | ⏳ `Queued (Wave 5)`      | ⏳ `Queued (Wave 5)`   | ⏳ `Queued (Wave 5)` |
| **Cisco Foundation-Sec-8B-Reasoning** (`W5`)          | Security & Guardrails (`jero-manager#31`)                           | `llama` · `Q4_K_M` (—)       | Implemented Arch (`llama`) / Planned Sec Policy   | ⏳ `Queued (Wave 5)`   | ⏳ `Queued (Wave 5)` | ⏳ `Queued (Wave 5)`      | ⏳ `Queued (Wave 5)`   | ⏳ `Queued (Wave 5)` |
| **Llama-Guard-3-8B** (`W5`)                           | Security & Guardrails (`jero-manager#31`)                           | `llama` · `Q4_0` (—)         | Implemented Arch (`llama`) / Planned Guardrail    | ⏳ `Queued (Wave 5)`   | ⏳ `Queued (Wave 5)` | ⏳ `Queued (Wave 5)`      | ⏳ `Queued (Wave 5)`   | ⏳ `Queued (Wave 5)` |
| **Llama-3.1-8B-Instruct** (`W5`)                      | Meta Llama 3.1 (`jero-engine#10`)                                   | `llama` · `Q4_K_M` (—)       | Implemented (`jero-arch-llama`)                   | ⏳ `Queued (Wave 5)`   | ⏳ `Queued (Wave 5)` | ⏳ `Queued (Wave 5)`      | ⏳ `Queued (Wave 5)`   | ⏳ `Queued (Wave 5)` |
| **Qwen3-8B** (`W5`)                                   | Alibaba Qwen 3 (`jero-engine#33`)                                   | `qwen3` · `Q4_K_M` (—)       | Planned (`qwen3` QK-Norm)                         | ⏳ `Queued (Wave 5)`   | ⏳ `Queued (Wave 5)` | ⏳ `Queued (Wave 5)`      | ⏳ `Queued (Wave 5)`   | ⏳ `Queued (Wave 5)` |
| **Gemma-2-9B-IT** (`W5`)                              | Google Gemma 2 (`jero-engine#22`)                                   | `gemma2` · `Q4_0` (—)        | Planned (`gemma2` Softcapping + SWA)              | ⏳ `Queued (Wave 5)`   | ⏳ `Queued (Wave 5)` | ⏳ `Queued (Wave 5)`      | ⏳ `Queued (Wave 5)`   | ⏳ `Queued (Wave 5)` |
| **Nimble Action/Routing SLM** (`W5`)                  | Decision & Routing SLMs (`jero-engine#46`)                          | `qwen3` · `Q4_K_M` (—)       | Planned (Decision/Action SLM)                     | ⏳ `Queued (Wave 5)`   | ⏳ `Queued (Wave 5)` | ⏳ `Queued (Wave 5)`      | ⏳ `Queued (Wave 5)`   | ⏳ `Queued (Wave 5)` |
| **Gemma-3-12B-IT** (`W6`)                             | Google Gemma 3 (`jero-engine#22`)                                   | `gemma3` · `Q4_K_M` (—)      | Planned (`gemma3` 5:1 Hybrid SWA)                 | ⏳ `Queued (Wave 6)`   | ⏳ `Queued (Wave 6)` | ⏳ `Queued (Wave 6)`      | ⏳ `Queued (Wave 6)`   | ⏳ `Queued (Wave 6)` |
| **Mistral-Nemo-12B-Instruct** (`W6`)                  | Mistral Dense (`jero-engine#10`)                                    | `mistral` · `Q4_0` (—)       | Implemented (`jero-arch-mistral`)                 | ⏳ `Queued (Wave 6)`   | ⏳ `Queued (Wave 6)` | ⏳ `Queued (Wave 6)`      | ⏳ `Queued (Wave 6)`   | ⏳ `Queued (Wave 6)` |
| **Qwen2.5-Coder-14B-Instruct** (`W6`)                 | Alibaba Qwen 2.5 (`jero-engine#10 / #33`)                           | `qwen2` · `Q4_K_M` (—)       | Implemented (`jero-arch-llama` `qwen2`)           | ⏳ `Queued (Wave 6)`   | ⏳ `Queued (Wave 6)` | ⏳ `Queued (Wave 6)`      | ⏳ `Queued (Wave 6)`   | ⏳ `Queued (Wave 6)` |
| **Phi-4-14B** (`W6`)                                  | Microsoft Phi-4 (`jero-engine#10`)                                  | `phi3` · `Q4_K_M` (—)        | Implemented (`jero-arch-phi3` `phi4`)             | ⏳ `Queued (Wave 6)`   | ⏳ `Queued (Wave 6)` | ⏳ `Queued (Wave 6)`      | ⏳ `Queued (Wave 6)`   | ⏳ `Queued (Wave 6)` |
| **DeepSeek-V2-Lite-16B (MLA MoE)** (`W6`)             | DeepSeek MLA (`jero-engine#33`)                                     | `deepseek2` · `Q4_0` (—)     | Planned (`deepseek2` Multi-Head Latent Attention) | ⏳ `Queued (Wave 6)`   | ⏳ `Queued (Wave 6)` | ⏳ `Queued (Wave 6)`      | ⏳ `Queued (Wave 6)`   | ⏳ `Queued (Wave 6)` |
| **Mistral-Small-3.2-24B-Instruct** (`W7`)             | Mistral 3 Dense (`jero-engine#10`)                                  | `mistral3` · `Q4_K_M` (—)    | Implemented (`jero-arch-mistral` `mistral3`)      | ⏳ `Queued (Wave 7)`   | ⏳ `Queued (Wave 7)` | ⏳ `Queued (Wave 7)`      | ⏳ `Queued (Wave 7)`   | ⏳ `Queued (Wave 7)` |
| **Qwen3.8-27B** (`W7`)                                | Alibaba Qwen 3.8 (`jero-engine#33`)                                 | `qwen3` · `Q4_K_M` (—)       | Planned (`qwen3.8`)                               | ⏳ `Queued (Wave 7)`   | ⏳ `Queued (Wave 7)` | ⏳ `Queued (Wave 7)`      | ⏳ `Queued (Wave 7)`   | ⏳ `Queued (Wave 7)` |
| **Gemma-4-26B-A4B-IT (MoE)** (`W7`)                   | Google Gemma 4 (`jero-engine#22`)                                   | `gemma4` · `Q4_K_M` (—)      | Planned (`gemma4` MoE + KV Sharing)               | ⏳ `Queued (Wave 7)`   | ⏳ `Queued (Wave 7)` | ⏳ `Queued (Wave 7)`      | ⏳ `Queued (Wave 7)`   | ⏳ `Queued (Wave 7)` |
| **Qwen3-Coder-30B-A3B (MoE)** (`W7`)                  | Alibaba Qwen 3 MoE (`jero-engine#33`)                               | `qwen3moe` · `Q4_K_M` (—)    | Planned (`qwen3moe` 128-Expert MoE)               | ⏳ `Queued (Wave 7)`   | ⏳ `Queued (Wave 7)` | ⏳ `Queued (Wave 7)`      | ⏳ `Queued (Wave 7)`   | ⏳ `Queued (Wave 7)` |
| **Gemma-4-31B-IT** (`W8`)                             | Google Gemma 4 (`jero-engine#22`)                                   | `gemma4` · `Q4_K_M` (—)      | Planned (`gemma4` 31B Dense)                      | ⏳ `Queued (Wave 8)`   | ⏳ `Queued (Wave 8)` | ⏳ `Queued (Wave 8)`      | ⏳ `Queued (Wave 8)`   | ⏳ `Queued (Wave 8)` |
| **Qwen2.5-Coder-32B-Instruct** (`W8`)                 | Alibaba Qwen 2.5 (`jero-engine#10 / #33`)                           | `qwen2` · `Q4_K_M` (—)       | Implemented (`jero-arch-llama` `qwen2`)           | ⏳ `Queued (Wave 8)`   | ⏳ `Queued (Wave 8)` | ⏳ `Queued (Wave 8)`      | ⏳ `Queued (Wave 8)`   | ⏳ `Queued (Wave 8)` |
| **Qwen3.6-MoE** (`W8`)                                | Alibaba Qwen 3.6 MoE (`jero-engine#33`)                             | `qwen35moe` · `Q4_K_M` (—)   | Planned (`qwen35moe`)                             | ⏳ `Queued (Wave 8)`   | ⏳ `Queued (Wave 8)` | ⏳ `Queued (Wave 8)`      | ⏳ `Queued (Wave 8)`   | ⏳ `Queued (Wave 8)` |
| **Mixtral-8x7B-Instruct-v0.1 (`Q4_0`)** (`W8`)        | Mistral Sparse MoE (`jero-engine#10`)                               | `mixtral` · `Q4_0` (—)       | Implemented (`jero-arch-mistral` `mixtral`)       | ⏳ `Queued (Wave 8)`   | ⏳ `Queued (Wave 8)` | ⏳ `Queued (Wave 8)`      | ⏳ `Queued (Wave 8)`   | ⏳ `Queued (Wave 8)` |

______________________________________________________________________

## 3. Detailed 5-Way Runtime Performance Telemetry (`N = 3`, Greedy `T = 0.0`)

Physical execution metrics across completed runs on `worker-riscv64` (`n_ctx = 2048`, 64-token generation window, 3-run mean ± sample standard deviation):

| Model                                              | Runtime | Active Cores / Threads | Load (`s`) | Mean TTFT (`ms ± σ`) | Prefill (`tok/s ± σ`) | Decode (`tok/s ± σ`) | Peak RSS (`GiB`) |
| :------------------------------------------------- | :------ | :--------------------- | :--------: | :------------------: | :-------------------: | :------------------: | :--------------: |
| *(Wave 1 currently executing on `worker-riscv64`)* | —       | —                      |     —      |          —           |           —           |          —           |        —         |

______________________________________________________________________

## 4. Five-Pillar Open-Source Capability Matrix (`BenchLM` / `DeepEval` Taxonomy)

Evaluated identically across all supported runtimes on **50 canonical upstream open-source test-split items** (10 items per pillar at `temperature = 0.0`): [`TIGER-Lab/MMLU-Pro`](https://huggingface.co/datasets/TIGER-Lab/MMLU-Pro) (`MIT`), [`openai/gsm8k`](https://huggingface.co/datasets/openai/gsm8k) (`MIT`), [`openai/openai_humaneval`](https://huggingface.co/datasets/openai/openai_humaneval) (`MIT`, sandboxed Python unit-test `pass@1`), [`google/IFEval`](https://huggingface.co/datasets/google/IFEval) (`Apache-2.0`, programmatic constraint verification), and [`truthfulqa/truthful_qa`](https://huggingface.co/datasets/truthfulqa/truthful_qa) (`Apache-2.0`):

| Model (`Quant`)                                                  | Runtime | Composite (`0–100%`) | Reasoning (`MMLU-Pro`) | Math (`GSM8K`) | Coding (`HumanEval` `pass@1`) | Instruction (`IFEval`) | Calibration (`TruthfulQA`) |
| :--------------------------------------------------------------- | :------ | :------------------: | :--------------------: | :------------: | :---------------------------: | :--------------------: | :------------------------: |
| *(Wave 1 capability evaluation in progress on `worker-riscv64`)* | —       |          —           |           —            |       —        |               —               |           —            |             —              |

______________________________________________________________________

## 5. Refusal Diagnostics & Unsupported Architecture Breakdown

Exact fail-closed admission diagnostics and architectural refusal reasons recorded during comparative probing:

| Model                                           | Runtime | Status Classification | Diagnostic / Refusal Detail |
| :---------------------------------------------- | :------ | :-------------------- | :-------------------------- |
| *(Populated live as wave evaluations complete)* | —       | —                     | —                           |

______________________________________________________________________

## 6. Reproducing the 5-Way Comparative Suite

```bash
# 1. Verify hardware dedication on worker-riscv64 (zero competing CI/CD daemons, 28 GiB memlock):
ulimit -l  # Expected: 29360128 (28 GiB bounded ceiling)

# 2. Run jero-diag N=3 single-prompt admission & latency/throughput check:
jero-diag --model <checkpoint.gguf> --cores 0xFF00 --threads 8 --n-ctx 2048 --max-tokens 64 --repeat 3 --json

# 3. Run jero-diag 16-core (0xFFFF) X100+A100 heterogeneous IME row-split benchmark:
jero-diag --model <checkpoint.gguf> --cluster both --split row --ime on --cores 0xFFFF --threads 16 --n-ctx 2048 --max-tokens 64 --repeat 3 --json

# 4. Query catalogued 5-way comparative metrics in MuObserve:
muobserve-cli sql "SELECT metric_name, value_double, attributes_json FROM v_metrics WHERE metric_name LIKE 'k3.bench5way.%' ORDER BY timestamp_unix_nano DESC LIMIT 25"
```

## 🔗 Related Documentation

- [**Model-Runner Portal Home**](index.md)
- [**Quickstart Guide**](quickstart.md) | [**Full Reference Manual**](manual.md) | [**Hardware Tuning Guide**](tuning.md)
- [**MuObserve Distributed Observability & Regression Engine**](docs/crates/muobserve.md)
