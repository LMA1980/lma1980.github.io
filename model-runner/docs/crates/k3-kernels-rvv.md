# `kernels-rvv` Architecture & Crate Reference

**Crate**: `kernels-rvv`  
**Version**: `0.1.0` (Edition 2024, Rust 1.85)  
**Role**: VLA RVV 1.0 vector loops and SpacemiT A100 Matrix Engine (IME) acceleration  
**Repository**: [`LMA1980/kernels-rvv`](https://github.com/LMA1980/kernels-rvv)  
**Rustdoc Reference**: [`kernels_rvv` API Reference](../../api/kernels_rvv/index.html)

---

## 1. Purpose & System Context

`kernels-rvv` contains the low-level numerical computation kernels executed during neural network forward passes. It provides two levels of acceleration:
1. **Vector Length Agnostic (VLA) RVV 1.0**: Strip-mining vector loops adhering to the standard RISC-V "V" 1.0 specification. Works seamlessly on any vector length (e.g. `VLEN=256` on X100, `VLEN=1024` on A100).
2. **SpacemiT A100 Matrix Engine (`XSMTVDotII`)**: Dedicated integer matrix multiply-accumulate instructions available exclusively on Cluster 1 (Cores 8–15).

---

## 2. Key Public Types & Traits

### 2.1 `VectorKernel` Trait
Abstraction for hardware-accelerated vector operations:
```rust
pub trait VectorKernel: Send + Sync {
    fn dot_product_f32(&self, a: &[f32], b: &[f32]) -> f32;
    fn rmsnorm(&self, out: &mut [f32], x: &[f32], weight: &[f32], eps: f32);
    fn vec_dot_q4_k_m(&self, q4_bytes: &[u8], f32_weights: &[f32]) -> f32;
    fn softmax(&self, logits: &mut [f32]);
}
```

### 2.2 `BaselineKernel`
Software fallback implementing the `VectorKernel` trait using portable Rust code, ensuring bit-exact validation across all development and non-RISC-V hosts.

### 2.3 `ime::repack_tiles`
Utility for transforming standard row-major quantized weights into `8×16` `i8` tiled layouts expected by the hardware matrix multiplier.

---

## 3. Hardware Acceleration & Instruction Constraints

### 3.1 RVV 1.0 Vector Strip-Mining
Uses standard RISC-V vector assembly instructions (`vsetvli`, `vle32.v`, `vfmacc.vv`, `vfredusum.vs`). Because loops are vector-length agnostic, the same compiled binary runs on:
- Cluster 0 (`X100`): `vlenb = 32` bytes (`VLEN = 256` bits)
- Cluster 1 (`A100`): `vlenb = 128` bytes (`VLEN = 1024` bits)

### 3.2 SpacemiT A100 `XSMTVDotII` Matrix Unit
- Instructions:
  - `smt.vpack.vv` (`.word 0x6704102b`)
  - `smt.vmadot` (`.word 0xe304302b`)
- Operation: `8×16` `i8` × `8×16` `i8` → `8×8` `i32` accumulation in vector register pair `v0:v1`.
- **CRITICAL INVARIANT**: Never invoke matrix instructions on Cluster 0 (`X100`, cores 0–7). The X100 core lacks matrix execution units and immediately traps with `SIGILL` (Illegal Instruction).

---

## 4. Derived Weight Caching & IME Tile Layout

To eliminate runtime repacking overhead during inference, `k3-manager` uses `kernels-rvv` to pre-convert quantized weights into derived IME tiles (`ime_tile_8x16`):
- Keyed by `(source_digest, recipe_version, "ime_tile_8x16")`.
- Saved in `/var/lib/k3/derived/`.
- Parallelized across available cores using `rayon`.

---

## 5. Inter-Crate Dependencies

- **Imports**: `k3-core`, `rayon`
- **Consumers**: `k3-engine`
