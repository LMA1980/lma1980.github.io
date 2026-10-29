# `action-runner-ipc` Architecture & Crate Reference

**Crate**: `action-runner-ipc`  
**Version**: `0.1.0` (Edition 2021)  
**Role**: Zero-copy wire protocol framing, Apache Fory stage control tasks, and Apache Arrow streaming RecordBatch serialization  
**Repository**: [`LMA1980/ActionRunner-ipc`](https://github.com/LMA1980/ActionRunner-ipc)  
**Rustdoc Reference**: [`action_runner_ipc` API Reference](../../api/action_runner_ipc/index.html)

---

## 1. Purpose & System Context

`action-runner-ipc` defines the high-performance binary transport protocol used between `action-runner-controller` and `action-runner` worker agents over WebSocket and TCP connections.

It bridges three complementary serialization technologies:
1. **`zerocopy` Fixed-Size Framing**: Memory-aligned binary headers (`IpcHeader`) with magic bytes and payload lengths for instant zero-copy slice casting.
2. **Apache Fory Control Messages**: High-speed, schema-checked RPC tasks (`StageDispatchTask`, `StageResultReport`, `Heartbeat`).
3. **Apache Arrow Streaming Telemetry**: Columnar serialization for structured log streams and hardware benchmark metrics without serialization overhead.

---

## 2. Binary Framing & Header Specification

Every message transmitted over the wire begins with a 16-byte aligned `IpcHeader`:

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|       Magic: 0x41524950 ("ARIP")      |  Ver: 0x01   |MsgType |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                       Payload Length (u32)                    |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                       Sequence Number (u32)                   |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                       CRC-32 Checksum (u32)                   |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

### Protocol Invariants:
- **Magic Constant**: `0x41524950` ("ARIP"). Frames with invalid magic are rejected immediately.
- **Maximum Frame Length**: 16 MiB payload ceiling to prevent memory denial-of-service.
- **CRC-32 Verification**: Detects payload corruption over network transport.

---

## 3. Key Public Types & Tasks

### 3.1 `StageDispatchTask` (Apache Fory)
Carries execution instructions for a pipeline stage:
```rust
#[derive(Fory)]
pub struct StageDispatchTask {
    pub job_id: String,
    pub stage_id: String,
    pub repo_url: String,
    pub commit_sha: String,
    pub commands: Vec<String>,
    pub environment: HashMap<String, String>,
    pub timeout_seconds: u32,
    pub exclusive: bool,  // US-25: Exclusive target-node stage isolation
}
```

### 3.2 Apache Arrow Telemetry Stream
Logs and hardware metrics are batched into `arrow::record_batch::RecordBatch` with standard schema:
- `timestamp`: Timestamp(Microsecond)
- `stream`: Utf8 ("stdout" | "stderr")
- `message`: Utf8
- `cpu_cycles`: UInt64
- `instructions`: UInt64

---

## 4. Inter-Crate Dependencies

- **Imports**: `zerocopy`, `fory`, `arrow`, `crc32fast`, `thiserror`
- **Consumers**: `action-runner`, `action-runner-controller`
