# `k3-core` Architecture & Crate Reference

**Crate**: `k3-core`  
**Version**: `0.1.0` (Edition 2024, Rust 1.85)  
**Role**: Foundational types, zero-copy tensor views, core affinity resolution, execution context, and unified error taxonomy  
**Repository**: [`LMA1980/k3-core`](https://github.com/LMA1980/k3-core)  
**Rustdoc Reference**: [`k3_core` API Reference](../../api/k3_core/index.html)

---

## 1. Purpose & System Context

`k3-core` provides the shared foundational vocabulary and data structures used across the entire Model-Runner workspace. It defines:
- The zero-copy immutable tensor view contract (`TensorView<'a>`).
- Quantization format enumeration (`QuantType`: `Q4_K_M`, `Q8_0`, `F16`, `F32`).
- Hardware cluster affinity masks and the control-plane capacity resolver (`ControlPlaneCapacityConfig`, `ResolvedControlCapacity`).
- Unified error taxonomy (`K3Error`).
- Architecture recipe contracts (`ArchRecipe`, `ExecutionContext`).

It intentionally avoids heavy runtime dependencies, depending only on `thiserror`, `zerocopy`, `serde`, and lightweight utilities.

---

## 2. Key Public Types & Data Structures

### 2.1 `TensorView<'a>`
A zero-copy borrowing slice across contiguous tensor memory:
```rust
pub struct TensorView<'a> {
    pub name: &'a str,
    pub shape: &'a [usize],
    pub strides: &'a [usize],
    pub quant_type: QuantType,
    pub data: &'a [u8],
}
```

### 2.2 `QuantType`
Represents hardware-supported weight quantization formats:
- `QuantType::F32`: Standard single-precision IEEE 754 float.
- `QuantType::F16`: Half-precision IEEE 754 float.
- `QuantType::Q8_0`: 8-bit symmetric block quantization (32 values per block).
- `QuantType::Q4_K_M`: Mixed 4-bit/6-bit k-quantization format for optimal perplexity/speed on SpacemiT K3.

### 2.3 Hardware Affinity Masks
Canonical constants modeling the SpacemiT Key Stone K3 SoC:
- `X100_CLUSTER_MASK: u64 = 0x00FF` (Cluster 0: Cores 0–7)
- `A100_CLUSTER_MASK: u64 = 0xFF00` (Cluster 1: Cores 8–15)
- `DEFAULT_ACTIVE_CONTROL_MASK: u64 = 0x00C0` (Cores 6–7)
- `DEFAULT_SPARE_RECOVERY_MASK: u64 = 0x0020` (Core 5)
- `DEFAULT_X100_COMPUTE_CAP_MASK: u64 = 0x003F` (Cores 0–5, max 6 threads)

### 2.4 `ControlPlaneCapacityConfig` & `ResolvedControlCapacity`
```rust
pub struct ControlPlaneCapacityConfig {
    pub active_control_cores: u32,
    pub spare_recovery_cores: u32,
    pub x100_online_mask: u64,
}

pub struct ResolvedControlCapacity {
    pub active_control_mask: u64,
    pub spare_recovery_mask: u64,
    pub x100_compute_cap_mask: u64,
    pub active_control_cores: u32,
    pub spare_recovery_cores: u32,
    pub max_x100_compute_threads: u32,
}
```

---

## 3. Interface Contracts & Traits

### 3.1 `ArchRecipe`
Defines the forward-pass execution graph for a neural network architecture:
```rust
pub trait ArchRecipe: Send + Sync {
    fn architecture_id(&self) -> &'static str;
    fn recipe_version(&self) -> &'static str;
    fn validate_weights(&self, weights: &ModelWeights) -> Result<(), K3Error>;
    fn execute_forward(
        &self,
        ctx: &mut ExecutionContext,
        token_id: u32,
    ) -> Result<u32, K3Error>;
}
```

### 3.2 `ExecutionContext`
Encapsulates single-prompt execution state:
- Pointers to model weights.
- Current sequence position / KV cache offset.
- Working activation scratchpads.
- Thread barrier synchronization references.

---

## 4. Diagnostics & Error Taxonomy (`K3Error`)

All subcrates surface platform errors using `K3Error`:
- `InsufficientLockableMemory`: Memory footprint exceeds physical RAM or `RLIMIT_MEMLOCK` ceiling.
- `CapabilityMismatch`: Model format or tensor quantization unsupported by compiled recipes.
- `ContextLengthExceeded`: Request sequence length overflows pre-allocated context bounds (`n_ctx`).
- `AffinityError`: Worker placement encroaches on dedicated control cores (`0x00C0`) or exceeds compute cap (`0x003F`).
- `QueueSaturated`: Admission queue depth cap exceeded.
- `RoutingUnavailable`: Internal decision model could not find an available route.
- `TensorBoundsError`: Offset or length exceeds raw tensor buffer boundaries.

---

## 5. Invariants & Conventions

1. **Rust Integer Discipline**: `usize` is used for indexing collections, array slices, and memory allocations. `u32` is used for token IDs, core counts, thread counts, and hardware domain parameters.
2. **Determinism**: Configuration validation and mask resolution are completely deterministic with zero side effects.
3. **No Allocation in Inner Loops**: Tensor view slices borrow directly from memory-mapped files without allocating vectors.

---

## 6. Inter-Crate Dependencies

- **Imports**: `thiserror`, `serde`, `zerocopy`
- **Consumers**: `k3-kv`, `k3-engine`, `k3-manager`, `kernels-rvv`, `arch-synthetic`, `k3-tokenizer`
