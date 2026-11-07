# Jero-Mu Milestone 2 Documentation Portal

<p align="center">
  <a href="https://github.com/LMA1980/MuConsole">
    <img src="../../assets/logos/muconsole-vector-badge.svg" alt="MuConsole (Void Console) Vector Badge — >_∅ P1+P3" width="128"/>
  </a>
</p>

Welcome to the documentation portal for **Jero-Mu Milestone 2** (*Declarative Configuration, Isolation & Continuous Delivery*).

Milestone 2 establishes the production foundation for the distributed K3 compute fabric, introducing declarative pipeline orchestration, multi-layer kernel and hypervisor sandboxing, an internal Cargo Sparse artifact registry, and zero-downtime A/B continuous delivery.

______________________________________________________________________

## 📚 Milestone 2 Developer & Architecture Guides

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Jero-Mu Platform Architecture                   │
├──────────────────────────────────┬─────────────────────────────────────┤
│ 1. Declarative CI/CD Pipelines   │ 2. Sandboxing & Privilege Model     │
│    ActionRunner.yml (Version 3)  │    MuIsolation (Kernel & MicroVM)   │
│    • 3-Tier: Tasks, Stages, DAG  │    • 3-Layer Monotonic Attenuation  │
│    • Compile-time ToolAdapters   │    • Landlock, Namespaces, seccomp  │
│    • Zero Shell Metacharacters   │    • KVM (RISC-V H-ext & Intel VT-x)│
├──────────────────────────────────┼─────────────────────────────────────┤
│ 3. Artifact & Package Storage    │ 4. Zero-Downtime Deployment (CD)    │
│    MuRegist (Cargo Sparse Index) │    MuConDe (A/B Subvolumes)         │
│    • RFC 2789 Sparse HTTP Index  │    • Btrfs Subvolume Snapshots      │
│    • SHA-256 CAS & DuckDB Catalog│    • Atomic symlink() + rename()    │
│    • Canary Release Promotion API│    • < 1s Watchdog Rollback & Taint │
└──────────────────────────────────┴─────────────────────────────────────┘
```

### 1. Declarative Pipeline Configuration

- [**ActionRunner.yml Syntax Reference**](actionrunner-syntax.md) (`actionrunner-syntax.md` — Issue [#10](https://github.com/LMA1980/lma1980.github.io/issues/10))
  - Complete Version 3 schema specification: `tasks`, `stages`, `on_action`, and `sccache` (`disabled`, `try`, `mandatory`).
  - Compile-time `ActionRunner-tools` `ToolAdapter` registry and strict shell metacharacter prohibition (`ProhibitedShellInvocation`).
  - Distributed compilation caching via `sccache`: capability-aware stage scheduling (`effective_stage_tags`), pre-stage daemon health checks & S3 vs. `Local disk` hijack auto-recovery, and step-by-step operator self-service setup (`/etc/action-runner/sccache.env`).
  - Topological stage DAG resolution, cycle detection (`CycleDetected`), `exclusive: true` worker draining, and `max_concurrent_per_node: 1` single-slot execution.
  - Three-phase configuration migration strategy from legacy `.actionrunner/on-*.yml`.

### 2. Multi-Layer Sandboxing & Isolation

- [**MuIsolation Dual-Backend Sandbox Model**](isolation-model.md) (`isolation-model.md` — Issue [#11](https://github.com/LMA1980/lma1980.github.io/issues/11))
  - 3-Layer monotonic privilege attenuation: Host Ceiling (`/etc/mu-isolation/ceiling.yml`) $\\cap$ Repository Profile (`.actionrunner/security.yml`) $\\cap$ Task Constraints $\\to$ fail-closed `SecurityGrantDenied`.
  - `KernelSandbox`: Linux Landlock LSM, namespaces (`CLONE_NEWNS`, `CLONE_NEWNET`, `CLONE_NEWPID`), cgroupv2, `PR_SET_NO_NEW_PRIVS`, seccomp-bpf, bounded `RLIMIT_MEMLOCK` (28 GiB / `29360128 KB`), and conditional `/proc/set_ai_thread` registration on SpacemiT A100 matrix clusters.
  - `HypervisorSandbox`: Hardware-assisted `/dev/kvm` microVMs on RISC-V Hypervisor (`H`) extension and Intel VT-x.

### 3. Artifact Registry & Package Distribution

- [**MuRegist Cargo Sparse Registry Guide**](muregist-guide.md) (`muregist-guide.md` — Issue [#14](https://github.com/LMA1980/lma1980.github.io/issues/14))
  - RFC 2789 Cargo Sparse HTTP Index endpoints and client `.cargo/config.toml` setup.
  - Native `cargo publish` binary multipart framing upload (`PUT /api/v1/crates/new`).
  - SHA-256 Content-Addressed Store (CAS) layout with atomic temporary file writes and embedded DuckDB metadata catalog.
  - Canary staging API (`POST /api/v1/canary/publish`, `GET /api/v1/canary/status`, `POST /api/v1/canary/{digest}/taint`, `POST /api/v1/canary/{digest}/promote`) with `step-ca` mTLS and Argon2id scoped bearer tokens.

### 4. Continuous Delivery & Zero-Downtime Rollouts

- [**MuConDe Continuous Delivery A/B Deployment Guide**](muconde-guide.md) (`muconde-guide.md` — Issue [#15](https://github.com/LMA1980/lma1980.github.io/issues/15))
  - Declarative deployment contracts (`.muconde/MuConDe.yml`) with automated integration test gating.
  - Idle cluster polling (`active_slots == 0`) and TTL-bounded deployment leases to eliminate CI/CD resource contention.
  - Dual Btrfs subvolumes (`@a` and `@b` under `/srv/muconde/<service>/`) with atomic symlink pointer swaps (`symlink()` + `rename()`).
  - Active post-swap health watchdog and sub-second instant rollback (`< 1s`) with automatic candidate digest tainting on MuRegist.

______________________________________________________________________

## 🔒 Ecosystem Governance & Invariants

All components documented across Milestone 2 adhere strictly to the following foundational invariants:

1. **Two-Tier Licensing Policy**:
   - **Libraries, IPC Crates & Sandboxing Engines (`LGPL-3.0-only WITH LGPL-3.0-linking-exception`)**: `MuIsolation`, `ActionRunner-ipc`, `MuConDe-ipc`, `ActionRunner-tools`.
   - **Daemons, Controllers, Agents & Web Frontends (`AGPL-3.0-only`)**: `ActionRunner-controller`, `MuRegist`, `MuConDe-controller`, `MuConDe-agent`.
1. **Monotonic Privilege Attenuation**: Security grants may only be narrowed downstream. Attempts to escalate privileges beyond an operator ceiling fail closed prior to process execution.
1. **Bounded Memory Ceilings**: Production nodes restrict `RLIMIT_MEMLOCK` to bounded limits (e.g. 28 GiB on 32 GB RAM nodes) to prevent kernel slab exhaustion.
1. **Zero Lab Topology Leakage**: Public documentation, issues, and code must use generic placeholders (`worker-riscv64`, `ci.internal`, `192.0.2.10`) and never expose private lab infrastructure.
