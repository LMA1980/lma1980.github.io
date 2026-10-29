# `arch-synthetic` Architecture & Crate Reference

**Crate**: `arch-synthetic`  
**Version**: `0.1.0` (Edition 2024, Rust 1.85)  
**Role**: Synthetic reference architecture recipe for deterministic testing, verification, and end-to-end integration  
**Repository**: [`LMA1980/arch-synthetic`](https://github.com/LMA1980/arch-synthetic)  
**Rustdoc Reference**: [`arch_synthetic` API Reference](../../api/arch_synthetic/index.html)

---

## 1. Purpose & System Context

`arch-synthetic` implements a lightweight, fully synthetic reference neural network architecture recipe conforming to the `ArchRecipe` trait from `k3-core`.

In distributed and embedded systems testing, downloading and memory-mapping real multi-gigabyte LLM weights (e.g. Qwen2.5 7B, 4.1 GB) is slow, consumes constrained memory, and introduces non-deterministic floating-point differences across architectures. `arch-synthetic` solves this:
- Generates synthetic model weights deterministically from a small seed.
- Executes full multi-layer transformer forward passes (attention projections, RMSNorm, feed-forward network, residual addition, and greedy argmax sampling).
- Provides bit-equivalent expected outputs across x86_64, aarch64, and riscv64 hardware.
- Allows automated test suites and CI runners to verify thread barriers, cgroup isolation, UDS IPC, and watchdog recovery in milliseconds with a ~100 KB footprint.

---

## 2. Key Public Types & Recipe Contract

### 2.1 `SyntheticRecipe`
```rust
pub struct SyntheticRecipe {
    pub hidden_dim: usize,
    pub num_layers: usize,
    pub num_heads: usize,
    pub head_dim: usize,
    pub vocab_size: usize,
}
```

### 2.2 Execution Logic
- `validate_weights`: Validates that tensor shapes match the synthetic hyperparameter dimensions.
- `execute_forward`: Evaluates all layers sequentially using `kernels-rvv` vector operations.
- `sample_argmax`: Selects the token ID corresponding to the maximum logit value. In case of ties, it breaks deterministically by selecting the lowest token ID.

---

## 3. Configuration & Test Invariants

1. **Deterministic Verification**: For any fixed seed and prompt sequence, the generated output token stream is guaranteed to match the reference Golden Vector.
2. **Minimal Resource Requirements**: Runs cleanly within `n_ctx = 64` bounds without requiring elevated `LimitMEMLOCK` privileges.
3. **Architecture ID**: Declares `architecture_id: "synthetic"`, allowing `k3-manager` capability filters to route incoming synthetic test requests to the synthetic worker without downloading external weights.

---

## 4. Inter-Crate Dependencies

- **Imports**: `k3-core`, `kernels-rvv`
- **Consumers**: `k3-engine`, `k3-manager` (used across all end-to-end scenario integration tests)
