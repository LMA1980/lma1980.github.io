# `k3-tokenizer` Architecture & Crate Reference

**Crate**: `k3-tokenizer`  
**Version**: `0.1.0` (Edition 2024, Rust 1.85)  
**Role**: Decoupled tokenization, chat template evaluation, and streaming piece decoding on reserved active control threads  
**Repository**: [`LMA1980/k3-tokenizer`](https://github.com/LMA1980/k3-tokenizer)  
**Rustdoc Reference**: [`k3_tokenizer` API Reference](../../api/k3_tokenizer/index.html)

---

## 1. Purpose & System Context

`k3-tokenizer` provides self-contained token encoding and decoding decoupled entirely from compute worker processes.

Per ADR-025 and ADR-027:
- The control plane daemon (`k3-manager`) owns tokenization: it formats multi-turn conversational messages using model-specific Jinja chat templates (`ChatTemplate`), encodes text into token IDs, validates sequence lengths against context window bounds (`n_ctx`), and streams generated tokens back to HTTP/SSE clients.
- By decoupling tokenization from compute workers, prompt encoding runs on fast out-of-order general-purpose cores (Cluster 0 X100, cores 6–7) while compute workers remain 100% focused on matrix arithmetic on Cluster 1 A100.
- Even when compute workers are fully saturated with forward passes, incoming requests can be tokenized, validated, and admitted to queues without blocking.

---

## 2. Key Public Types & Traits

### 2.1 `Tokenizer` Trait
```rust
pub trait Tokenizer: Send + Sync {
    fn encode(&self, text: &str, add_bos: bool) -> Result<Vec<u32>, K3Error>;
    fn decode(&self, tokens: &[u32]) -> Result<String, K3Error>;
    fn vocab_size(&self) -> usize;
    fn bos_token_id(&self) -> Option<u32>;
    fn eos_token_id(&self) -> Option<u32>;
}
```

### 2.2 `GgufTokenizer` & `SimpleTokenizer`
- `GgufTokenizer`: Parses tokenizer vocabulary, merges, and scores embedded directly in GGUF model files (supporting BPE and WordPiece).
- `SimpleTokenizer`: Lightweight whitespace and byte-fallback tokenizer for unit testing and diagnostic pipelines.

### 2.3 `ChatTemplate`
Evaluates Jinja-compatible chat templates, structuring user, assistant, system, and tool call messages into canonical model prompts:
```rust
pub struct ChatTemplate {
    template: String,
    bos_token: Option<String>,
    eos_token: Option<String>,
}
```

### 2.4 `StreamingDetokenizer`
Incrementally decodes individual token IDs into valid UTF-8 strings. It handles:
- Multi-byte UTF-8 sequences split across successive tokens (buffering incomplete byte sequences).
- Multi-token stop sequences (e.g. `<|im_end|>`, `User:`), withholding candidate match prefixes until confirmed or discarded.

---

## 3. Control-Plane Invariants

1. **Non-Blocking Execution**: Tokenization and template expansion run strictly within the active control thread pool (`active_control_mask = 0x00C0`), never invoking worker processes.
2. **Context Window Admission Bounds**: If prompt token count exceeds the configured `n_ctx` ceiling, `k3-tokenizer` surfaces `K3Error::ContextLengthExceeded` upfront, causing the HTTP adapter to reject the request with HTTP 400 immediately rather than truncating silently.
3. **Byte Fallback**: Tokenizers implement byte fallback to prevent fatal crashes when unseen Unicode codepoints are encountered in user prompts.

---

## 4. Inter-Crate Dependencies

- **Imports**: `k3-core`, `minijinja`, `serde`, `serde_json`, `thiserror`
- **Consumers**: `k3-manager`
