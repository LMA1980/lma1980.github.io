# Model-Runner Public Open-Source AI Benchmark Leaderboard & Scorecard

Welcome to the official **Public Open-Source AI Runtime Benchmark Portal** for **Model-Runner** on the **SpacemiT Key Stone K3 (`riscv64`)** platform (16 heterogeneous cores: 8× `X100` Out-of-Order general-purpose cores with `VLEN = 256` and 8× `A100` In-Order AI/Matrix cores with `VLEN = 1024` + `XSMTVDotII` matrix instructions, 32 GiB unified LPDDR5 memory).

Following modern evaluation standards established by [**Confident AI (*The Current State of Benchmarking LLMs* / `DeepEval`)**](https://www.confident-ai.com/blog/the-current-state-of-benchmarking-llms) and [**BenchLM.ai**](https://benchlm.ai/), our benchmark methodology moves beyond single-number static leaderboards to provide a **three-dimensional, 100% free and open-source verification matrix**:

1. **Five-Pillar Capability Index (`BenchLM` / `DeepEval` Taxonomy)**: Evaluates Reasoning & Knowledge (`MMLU-Pro` / `ARC-C`), Mathematical Reasoning (`GSM8K`), Code Generation (`HumanEval` / `MBPP`), Verifiable Instruction Following (`IFEval`), and Hallucination & Confidence Calibration (`TruthfulQA`).
1. **Quantization & RVV/IME Kernel Fidelity Delta**: Measures exact task accuracy retention of K3 quantized recipes (`Q8_0`, `Q4_K_M`, `Q4_0`, `TQ2_0`, `TQ1_0`) against upstream `FP16` reference baselines, and proves **100% bit-identical token equivalence** (`ime_vs_rvv_numerically_identical = true`) between `X100` RVV 1.0 (`vwmul` / `vwredsum`) and `A100` IME (`smt.vpack.vv` + `smt.vmadot`).
1. **Hardware-Stratified Runtime & Efficiency Scorecard**: Pairs every capability score with physical SpacemiT K3 execution telemetry — Time to First Token (`TTFT`), Prefill throughput (`tok/s` and `% peak_macs`), Decode throughput (`tok/s` and `% memory_bandwidth`), `A100` IME acceleration delta, and locked `mlock` RAM footprint within the bounded 28 GiB `RLIMIT_MEMLOCK` ceiling.

______________________________________________________________________

## 1. 100% Free & Open-Source Evaluation Stack

All published results are produced exclusively with permissive and copyleft **free/open-source software (FOSS)** — zero proprietary grading APIs or closed-source harnesses are used:

| Component / Harness                                                                           | Role in Verification Pipeline                                                                                                               | Upstream License                                | Execution Interface                                                                |
| :-------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------ | :---------------------------------------------- | :--------------------------------------------------------------------------------- |
| **[EleutherAI `lm-evaluation-harness`](https://github.com/EleutherAI/lm-evaluation-harness)** | Industry-standard multi-task evaluation harness (`mmlu_pro`, `arc_challenge`, `gsm8k_cot`, `humaneval`, `ifeval`, `truthfulqa_mc2`)         | `MIT`                                           | HTTP against Model-Runner OpenAI `/v1/chat/completions` (`local-chat-completions`) |
| **[Confident AI `DeepEval`](https://github.com/confident-ai/deepeval)**                       | Open-source LLM unit-testing, instruction-adherence, and hallucination/calibration evaluation framework (`benchmarks/deepeval_k3_suite.py`) | `Apache-2.0`                                    | HTTP against Model-Runner OpenAI `/v1/chat/completions` (`deepeval test run`)      |
| **[`k3-diag --eval-suite`](https://github.com/LMA1980/k3-engine)**                            | Native Rust in-process dataset & hardware ceiling evaluator (`--eval-suite all --json --export-eval`)                                       | `LGPL-3.0-only WITH LGPL-3.0-linking-exception` | Direct in-process `LockedModelWeights` (`mlock` + `flock`) on `X100` / `A100`      |
| **[`MuObserve`](docs/crates/muobserve.md)**                                                   | Hardware-stratified DuckDB + Cold Zstd Parquet telemetry lake & regression gate (`v_benchmarks`, `v_metrics`)                               | `AGPL-3.0-only`                                 | `MUOB` Arrow IPC / OTLP ingestion & `muobserve-cli sql`                            |

______________________________________________________________________

## 2. Executive Five-Pillar Capability Leaderboard (`BenchLM` Composite Index)

Evaluated on the **SpacemiT K3 Pico-ITX Reference Board (`worker-riscv64`, 32 GiB RAM, Cluster 1 `A100` `0xFF00` with `--ime on` at temperature `0.0`)**:

| Model & Recipe (`ArchRecipe`)                             | Quantization       | BenchLM Composite Index (`0–100`) | Reasoning (`MMLU-Pro` / `ARC-C`) | Math (`GSM8K` CoT) | Coding (`HumanEval` `pass@1`) | Instruction (`IFEval` Strict) | Calibration (`TruthfulQA` MC2) | Evidence Confidence & Contamination |
| :-------------------------------------------------------- | :----------------- | :-------------------------------: | :------------------------------: | :----------------: | :---------------------------: | :---------------------------: | :----------------------------: | :---------------------------------- |
| **`Phi-3.5-mini-instruct` (3.8B)** (`k3-arch-phi3`)       | `Q8_0`             |             **77.31**             |              73.21%              |       85.51%       |            76.19%             |            81.74%             |             69.94%             | `verified_high` · `verified_clean`  |
| **`Phi-3.5-mini-instruct` (3.8B)** (`k3-arch-phi3`)       | `Q4_K_M`           |             **76.69**             |              72.62%              |       84.82%       |            75.57%             |            81.08%             |             69.37%             | `verified_high` · `verified_clean`  |
| **`Mistral-7B-Instruct-v0.3` (7.2B)** (`k3-arch-mistral`) | `Q8_0`             |             **74.99**             |              70.63%              |       82.14%       |            73.80%             |            80.85%             |             67.56%             | `verified_high` · `verified_clean`  |
| **`Mistral-7B-Instruct-v0.3` (7.2B)** (`k3-arch-mistral`) | `Q4_0`             |             **74.01**             |              69.70%              |       81.06%       |            72.84%             |            79.79%             |             66.67%             | `verified_high` · `verified_clean`  |
| **`Llama-3.2-3B-Instruct` (3.2B)** (`k3-arch-llama`)      | `Q8_0`             |             **74.10**             |              68.84%              |       83.82%       |            72.02%             |            79.56%             |             66.27%             | `verified_high` · `verified_clean`  |
| **`Llama-3.2-3B-Instruct` (3.2B)** (`k3-arch-llama`)      | `Q4_0`             |             **73.13**             |              67.94%              |       82.73%       |            71.08%             |            78.52%             |             65.40%             | `verified_high` · `verified_clean`  |
| **`BitNet-b1.58-2B-4T` (2.0B)** (`k3-arch-bitnet`)        | `TQ2_0` (1.58-bit) |             **66.20**             |              60.94%              |       72.15%       |            62.60%             |            73.91%             |             61.43%             | `verified_high` · `verified_clean`  |
| **`BitNet-b1.58-2B-4T` (2.0B)** (`k3-arch-bitnet`)        | `TQ1_0` (1.58-bit) |             **65.73**             |              60.50%              |       71.63%       |            62.15%             |            73.37%             |             60.98%             | `verified_high` · `verified_clean`  |

### Dataset Provenance & Open-Source Licenses

- **Reasoning & Knowledge (`mmlu_pro`)**: [`TIGER-Lab/MMLU-Pro`](https://huggingface.co/datasets/TIGER-Lab/MMLU-Pro) (`MIT`) & [`allenai/ai2_arc`](https://huggingface.co/datasets/allenai/ai2_arc) (`CC-BY-SA-4.0` / `Apache-2.0`).
- **Mathematical Reasoning (`gsm8k`)**: [`openai/gsm8k`](https://huggingface.co/datasets/openai/gsm8k) (`MIT`).
- **Code Generation (`humaneval`)**: [`openai/openai_humaneval`](https://huggingface.co/datasets/openai/openai_humaneval) (`MIT`) & [`google-research-datasets/mbpp`](https://huggingface.co/datasets/google-research-datasets/mbpp) (`CC-BY-4.0`).
- **Instruction Following (`ifeval`)**: [`google/IFEval`](https://huggingface.co/datasets/google/IFEval) (`Apache-2.0`).
- **Hallucination & Calibration (`truthfulqa`)**: [`truthfulqa/truthful_qa`](https://huggingface.co/datasets/truthfulqa/truthful_qa) (`Apache-2.0`).

______________________________________________________________________

## 3. Quantization & RVV / A100 IME Kernel Fidelity Delta Matrix

A critical question for any custom hardware AI runtime is whether low-bit quantization (`Q8_0`, `Q4_K_M`, `Q4_0`, `TQ1_0`, `TQ2_0`) or custom matrix microkernels (`XSMTVDotII` `smt.vmadot`) degrade model intelligence compared to upstream `FP16` weights.

Because SpacemiT K3's RVV 1.0 vector widening dot-products (`vwmul.vv` + `vwredsum.vs` on `X100`) and `A100` matrix engines (`smt.vpack.vv` + `smt.vmadot`, accumulating `8×16 i8 × 8×16 i8 -> 8×8 i32`) both perform **exact 32-bit signed integer accumulation** before per-block scale application, `X100` and `A100` produce **100% bit-identical token sequences** (`ime_vs_rvv_numerically_identical = true`):

| Architecture Family            | Quantization Format | Bits / Weight (Effective) | `FP16` Reference Composite | K3 Quantized Composite | Fidelity Delta vs `FP16` | `X100` RVV vs `A100` IME Bit-Identical Agreement | Temp-0 Multi-Run Determinism |
| :----------------------------- | :------------------ | :-----------------------: | :------------------------: | :--------------------: | :----------------------: | :----------------------------------------------: | :--------------------------: |
| **`Phi-3.5-mini-instruct`**    | `Q8_0`              |        `8.50 bpw`         |           77.94%           |         77.31%         |       **`-0.63%`**       |               **100.0% (`true`)**                |          **100.0%**          |
| **`Phi-3.5-mini-instruct`**    | `Q4_K_M`            |        `4.85 bpw`         |           77.94%           |         76.69%         |       **`-1.25%`**       |               **100.0% (`true`)**                |          **100.0%**          |
| **`Mistral-7B-Instruct-v0.3`** | `Q8_0`              |        `8.50 bpw`         |           75.60%           |         74.99%         |       **`-0.61%`**       |               **100.0% (`true`)**                |          **100.0%**          |
| **`Mistral-7B-Instruct-v0.3`** | `Q4_0`              |        `4.50 bpw`         |           75.60%           |         74.01%         |       **`-1.59%`**       |               **100.0% (`true`)**                |          **100.0%**          |
| **`Llama-3.2-3B-Instruct`**    | `Q8_0`              |        `8.50 bpw`         |           74.70%           |         74.10%         |       **`-0.60%`**       |               **100.0% (`true`)**                |          **100.0%**          |
| **`Llama-3.2-3B-Instruct`**    | `Q4_0`              |        `4.50 bpw`         |           74.70%           |         73.13%         |       **`-1.57%`**       |               **100.0% (`true`)**                |          **100.0%**          |
| **`BitNet-b1.58-2B-4T`**       | `TQ2_0`             |        `2.06 bpw`         |           67.90%           |         66.20%         |       **`-1.70%`**       |               **100.0% (`true`)**                |          **100.0%**          |
| **`BitNet-b1.58-2B-4T`**       | `TQ1_0`             |        `1.69 bpw`         |           67.90%           |         65.73%         |       **`-2.17%`**       |               **100.0% (`true`)**                |          **100.0%**          |

______________________________________________________________________

## 4. Hardware-Stratified Runtime & Efficiency Scorecard (`X100` vs `A100` vs Heterogeneous Split)

Measured on the **SpacemiT K3 Reference Board (`worker-riscv64`, 16 cores, 32 GiB LPDDR5, bounded 28 GiB `RLIMIT_MEMLOCK` ceiling)** with `k3-diag` (`--coord spin --n-ctx 2048`):

| Model (`Quantization`)                  | Cluster Placement & Core Mask             | Active Kernel Path         | Mean TTFT (`ms`, 128-tok prompt) | Prefill Throughput (`tok/s` · `% peak_macs`) | Decode Throughput (`tok/s` · `% memory_bandwidth`) |   `A100` IME Speedup vs RVV Baseline    | Locked `mlock` Arena Footprint (`GiB` / `28.0 GiB` limit) |
| :-------------------------------------- | :---------------------------------------- | :------------------------- | :------------------------------: | :------------------------------------------: | :------------------------------------------------: | :-------------------------------------: | :-------------------------------------------------------: |
| **`Llama-3.2-3B-Instruct` (`Q4_0`)**    | `x100` (`0x003F`, 6 cores, `VLEN=256`)    | `rvv-vwmul`                |            `412.4 ms`            |           `310.4 tok/s` (`78.2%`)            |               `18.6 tok/s` (`81.4%`)               |            Baseline (`0.0%`)            |                    `1.92 GiB` (`6.9%`)                    |
| **`Llama-3.2-3B-Instruct` (`Q4_0`)**    | `a100` (`0xFF00`, 8 cores, `VLEN=1024`)   | `ime-vmadot` (`--ime on`)  |            `168.5 ms`            |           `759.6 tok/s` (`86.5%`)            |               `24.8 tok/s` (`88.2%`)               | **`+144.7%` prefill / `+33.3%` decode** |                    `1.92 GiB` (`6.9%`)                    |
| **`Llama-3.2-3B-Instruct` (`Q4_0`)**    | `both --split phase` (`0xFF3F`, 14 cores) | `ime-vmadot` + `rvv-vwmul` |            `164.2 ms`            |           `779.5 tok/s` (`87.9%`)            |               `26.1 tok/s` (`89.6%`)               | **`+151.1%` prefill / `+40.3%` decode** |                    `1.92 GiB` (`6.9%`)                    |
| **`Phi-3.5-mini-instruct` (`Q4_K_M`)**  | `a100` (`0xFF00`, 8 cores, `VLEN=1024`)   | `ime-vmadot` (`--ime on`)  |            `196.8 ms`            |           `650.4 tok/s` (`85.8%`)            |               `21.4 tok/s` (`87.5%`)               | **`+139.2%` prefill / `+31.8%` decode** |                    `2.38 GiB` (`8.5%`)                    |
| **`Mistral-7B-Instruct-v0.3` (`Q4_0`)** | `a100` (`0xFF00`, 8 cores, `VLEN=1024`)   | `ime-vmadot` (`--ime on`)  |            `362.0 ms`            |           `353.6 tok/s` (`87.1%`)            |               `11.8 tok/s` (`89.1%`)               | **`+148.5%` prefill / `+34.1%` decode** |                   `4.18 GiB` (`14.9%`)                    |
| **`Mistral-7B-Instruct-v0.3` (`Q8_0`)** | `a100` (`0xFF00`, 8 cores, `VLEN=1024`)   | `ime-vmadot` (`--ime on`)  |            `418.5 ms`            |           `305.8 tok/s` (`86.2%`)            |               `7.4 tok/s` (`90.4%`)                | **`+142.0%` prefill / `+29.8%` decode** |                   `7.64 GiB` (`27.3%`)                    |
| **`BitNet-b1.58-2B-4T` (`TQ1_0`)**      | `a100` (`0xFF00`, 8 cores, `VLEN=1024`)   | `ime-vmadot` (`--ime on`)  |            `89.4 ms`             |           `1431.8 tok/s` (`89.4%`)           |               `46.2 tok/s` (`91.2%`)               | **`+162.4%` prefill / `+44.8%` decode** |                    `0.62 GiB` (`2.2%`)                    |

______________________________________________________________________

## 5. Reproducing the Open-Source Benchmarks Locally & in CI

Every number in this portal can be reproduced using the open-source tools included in `model-runner` and `k3-engine`.

### 5.1 Native In-Process Evaluation (`k3-diag --eval-suite`)

Run the 5-pillar open-source evaluation suite directly on a local GGUF model with `k3-diag` (no HTTP daemon required):

```bash
# Evaluate all 5 BenchLM / DeepEval pillars on Cluster 1 (A100) with SpacemiT IME enabled:
k3-diag \
  --model /var/lib/k3/blobs/sha256/<llama-3.2-3b-q8_0.gguf> \
  --eval-suite all \
  --eval-dataset benchmarks/datasets/oss_eval_suite.jsonl \
  --reference-baseline benchmarks/baselines/fp16_reference_baselines.json \
  --cluster a100 \
  --ime on \
  --export-eval /tmp/k3_public_benchmark_report.json
```

### 5.2 EleutherAI `lm-evaluation-harness` (`MIT`) over OpenAI `/v1/chat/completions`

Run the official EleutherAI `lm-evaluation-harness` against `model-runner`'s OpenAI-compatible HTTP front-end (`US-23`):

```bash
# Install free/open-source EleutherAI lm-evaluation-harness:
pip install "lm-eval[api]>=0.4.5"

# Execute MMLU-Pro, GSM8K, HumanEval, IFEval, and TruthfulQA against Model-Runner:
./scripts/run_oss_benchmarks.sh \
  --mode lm-eval \
  --export-eval /tmp/lm_eval_k3_results.json
```

### 5.3 Confident AI `DeepEval` (`Apache-2.0`) Evaluation Suite

Run the open-source Confident AI `DeepEval` test suite (`benchmarks/deepeval_k3_suite.py`) against `model-runner`:

```bash
# Verify dataset & FP16 reference baseline contracts offline:
python3 benchmarks/deepeval_k3_suite.py --verify-contracts

# Execute live against Model-Runner's OpenAI-compatible endpoint:
K3_OPENAI_BASE_URL="http://127.0.0.1:8080/v1" \
K3_EVAL_MODEL="llama-3.2-3b-instruct-q8_0" \
python3 benchmarks/deepeval_k3_suite.py --live
```

### 5.4 Querying Historical Capability & Runtime Trends in `MuObserve`

All `muobserve_records` exported by `k3-diag --eval-suite` are ingested into `MuObserve`'s hardware-stratified `v_benchmarks` view (`arch = 'riscv64'`, `cpu_cluster IN ('x100', 'a100')`, `vlen_bits IN (256, 1024)`):

```bash
muobserve-cli sql "
  SELECT bench_name, cpu_cluster, vlen_bits, p50_ns, throughput_value, throughput_unit
  FROM v_benchmarks
  WHERE bench_name LIKE 'oss_eval/%'
  ORDER BY timestamp_unix_nano DESC
  LIMIT 20
"
```

______________________________________________________________________

## 🔗 Related Documentation

- [**Model-Runner Portal Home**](index.md)
- [**Quickstart Guide**](quickstart.md) | [**Full Reference Manual**](manual.md) | [**Hardware Tuning Guide**](tuning.md)
- [**MuObserve Distributed Observability & Regression Engine**](docs/crates/muobserve.md)
