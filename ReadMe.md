# LMA1980

Welcome to the project portal for open-source systems, native RISC-V solutions, and software incubators.

## ActionRunner Solution

Lightweight, native GitHub Webhook CI execution sidecar and real-time observability suite designed for bare-metal RISC-V hardware (SpacemiT Key Stone K3). It serializes builds with event coalescing, executes automated test and hygiene pipelines, calculates factory quality scores, and serves dynamic SVG status cards.

- [**ActionRunner-rs**](https://github.com/LMA1980/ActionRunner-rs) — High-performance GitHub Webhook daemon and CI execution sidecar written in Rust. Features coalescing FIFO queues, HMAC-SHA256 signature verification, automated workspace synchronization, pipeline quality scoring (`cargo llvm-cov`, `cargo clippy`, `cargo audit`, benchmarks), and dynamic SVG status cards.
- [**ActionRunner-web**](https://github.com/LMA1980/ActionRunner-web) — WebAssembly queue monitor and job drill-down dashboard built with Leptos (CSR). Provides real-time build status, individual submodule scorecards, and step-by-step CI execution logs.

## Model Runner Solution

High-performance, distributed AI inference runtime and control plane engineered specifically for the SpacemiT Key Stone K3 SoC (16 heterogeneous RISC-V cores across general-purpose and vector/matrix clusters, 32 GB unified memory). Built around cycle-exclusive execution, systemd cgroup isolation, and hardware-accelerated RVV 1.0 / IME compute kernels.

Public repositories composing the solution:
- [**k3-core**](https://github.com/LMA1980/k3-core) — Foundational core abstractions, quantization types (`QuantType`), zero-copy tensor views (`TensorView`), single-prompt execution contexts, and structured platform diagnostics (`K3Error`).
- [**k3-kv**](https://github.com/LMA1980/k3-kv) — Policy-free context memory holder daemon managing bounded `mlock` shared-memory arenas and passing arena file descriptors over Unix Domain Sockets (`SCM_RIGHTS`) to survive worker restarts.
- [**k3-engine**](https://github.com/LMA1980/k3-engine) — Low-level compute runtime implementing unified VLA RVV 1.0 vector loops, A100 IME matrix acceleration, thread-group synchronization, and paged KV cache allocation.
- [**k3-manager**](https://github.com/LMA1980/k3-manager) — Orchestration daemon and control plane handling session state and content-addressed model catalogs in DuckDB, IPC serialization over Unix Domain Sockets + shared memory, and modular OpenAI/Anthropic compatible APIs.

### Documentation Portal

Complete architectural, developer, and operator documentation for the Model-Runner ecosystem is published in the portal:

- [**Model Runner Documentation Portal**](model-runner/) — Comprehensive portal landing page.
- **End-User Guides**: [Quickstart Guide](model-runner/quickstart.md) | [Full Reference Manual](model-runner/manual.md)
- **Operator Runbooks**: [Deployment & Maintenance Guide](model-runner/deployment.md) | [Troubleshooting Guide](model-runner/troubleshooting.md) | [Hardware Tuning Guide](model-runner/tuning.md)
- **Architecture & API**: [Crate Reference Guides](model-runner/docs/crates/) | [Rustdoc API Reference](model-runner/api/)

---

## Incubator Projects

Documentation for incubator projects and early-stage prototypes.

### Jero-Mu (제로 무)

An incubator project for a distributed application model, I will attempt to write it in Rust or in C#, and any other appropriate language to work with this solution.

#### api.jelomu.local

A Rocket (v0.6-dev) integration to provide a distributable WebAPI.
 - /about
    - Provides runtime information on the current runtime.
 - Still a work in progress

The goal will be to support both public and mTLS authenticated requests. [planned]
 - The idea is to provide the end-users the guide-lines to generate CSR for gaining access.
 - Document the steps required by the operator to support mTLS server-side.
 - Establish usage policy.
 - Still require to authenticate the client user with either
    - Username / Password or Passphrase
    - Short lived Token
  
Provide an authentication mechanism [planned]
 - Use the host own public key to encrypt the password: forcing decryption by the host private key.
 - Use a username@realm-identifier
 - Return default role along with an associated session-token: minimal-authorized-access

Provide an authorization mechanism [planned]
 - A given user may have access to one or many role
 - minimal-authorized-access provides the following policy
     - get-about
     - get-about-detailed
     - ...
  - anonymous-access provides the following policy (applies to tokenless requests)
     - get-about
     - ...

#### neuron-rs (neuron)

A minimal distributed compute unit: the idea is to be able to support links to resources. No transport involved at this level.

[milestone-1](neuron-rs/milestone-1.md)

#### neuron-runner-rs (neuron-runner)[planned]

A minimal runtime environment for neurons implementation. Transport layer to be determined.

### [workspace-builder](https://github.com/LMA1980/workspace-builder)

A tool to help compile multiple ABI targets when building a cargo project.
