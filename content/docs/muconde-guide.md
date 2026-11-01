# MuConDe Continuous Delivery & A/B Zero-Downtime Deployment Guide

This document details the architecture, configuration contracts, and operational execution flows of **MuConDe** (Continuous Delivery orchestrator composed of `MuConDe-ipc` `LGPL-3.0-only WITH LGPL-3.0-linking-exception`, and `MuConDe-controller` / `MuConDe-agent` `AGPL-3.0-only`).

______________________________________________________________________

## 1. Architectural Mission

MuConDe delivers reliable, zero-downtime blue/green (A/B) continuous delivery on bare-metal and edge RISC-V compute nodes. It solves two critical challenges in bare-metal infrastructure:

1. **Resource Contention with CI**: Competing compile jobs and production runtime services can exhaust RAM and cause cache degradation. MuConDe implements idle cluster polling and TTL-bounded deployment leases to ensure deployments occur strictly when worker nodes are quiescent.
1. **Deterministic Zero-Downtime Rollouts & Sub-Second Rollback**: By leveraging Btrfs subvolume snapshots (`@a` and `@b`) paired with atomic filesystem symlink swaps and health watchdogs, deployments achieve instantaneous cutover and sub-second rollback (`< 1s`) if a canary build degrades.

```
┌────────────────────────────────────────────────────────────────────────┐
│                        MuConDe-controller                              │
│  1. Check CI status: active_slots == 0 && !exclusive_locked            │
│  2. Acquire TTL-bounded lease from ActionRunner-controller             │
│  3. Stage canary release from MuRegist                                 │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ IPC / mTLS
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                          MuConDe-agent                                 │
│                                                                        │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │ Btrfs Subvolume Management (/srv/muconde/<service>/)           │   │
│   │   slot_a (@a) ◄───► slot_b (@b)                                │   │
│   │                       ▲                                        │   │
│   │                       │ Atomic symlink() + rename()            │   │
│   │                    current                                     │   │
│   └───────────────────────┬────────────────────────────────────────┘   │
│                           │                                            │
│                           ▼                                            │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │ Post-Swap Health Watchdog (Bake Window: 30s)                   │   │
│   │   • Systemd ActiveState == active                              │   │
│   │   • HTTP /healthz == 200 OK                                    │   │
│   │   • IPC Ping Latency < 50ms                                    │   │
│   └───────────────────────┬────────────────────────────────────────┘   │
│                           │                                            │
│            ┌──────────────┴──────────────┐                             │
│            ▼ Success                     ▼ Failure                     │
│   ┌───────────────────┐        ┌───────────────────────────────────┐   │
│   │ Promote Canary    │        │ Sub-Second Rollback (< 1s)        │   │
│   │ Commit Btrfs Slot │        │ Atomic symlink back to slot_a     │   │
│   └───────────────────┘        │ MuRegist: POST canary/taint       │   │
│                                └───────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────┘
```

______________________________________________________________________

## 2. Declarative Contract: `.muconde/MuConDe.yml`

Services opting into automated continuous delivery define a `.muconde/MuConDe.yml` manifest at the repository root:

```yaml
version: "1"
service: "model-runner"

deployment:
  target_nodes:
    - "worker-riscv64"
  binary_name: "model-runner"
  systemd_unit: "model-runner.service"

integration_tests:
  - "unit-tests"
  - "vector-inference-smoke"
  - "kv-arena-stress"

health_check:
  http_endpoint: "http://127.0.0.1:8080/healthz"
  ipc_ping: true
  expected_status: 200
  timeout_seconds: 15

verification:
  bake_window_secs: 30
  rollback_on_failure: true
```

### Contract Fields

| Field                              | Type        | Description                                                          |
| :--------------------------------- | :---------- | :------------------------------------------------------------------- |
| `version`                          | string      | Configuration version. Currently `"1"`.                              |
| `service`                          | string      | Canonical service name matching the systemd unit and directory path. |
| `deployment.target_nodes`          | list        | Target node capability tags where the service runs.                  |
| `deployment.binary_name`           | string      | Executable binary deployed inside the slot subvolume.                |
| `deployment.systemd_unit`          | string      | Target `systemd` service unit managed by the agent.                  |
| `integration_tests`                | list/string | Required CI stage list, or `"all"` to require all pipeline stages.   |
| `health_check.http_endpoint`       | string      | Local HTTP health probe endpoint.                                    |
| `health_check.ipc_ping`            | boolean     | When `true`, issues an IPC ping over Unix Domain Socket.             |
| `verification.bake_window_secs`    | integer     | Continuous observation duration before finalizing deployment.        |
| `verification.rollback_on_failure` | boolean     | When `true`, triggers automatic revert upon failure.                 |

______________________________________________________________________

## 3. Idle Scheduling & Deployment Leases

To prevent CD rollouts from colliding with active CI compilation jobs or high-load benchmarks, MuConDe implements mutually exclusive lease negotiation with ActionRunner:

1. **Idle Cluster Polling**: Before initiating a deployment sequence, `MuConDe-controller` queries `ActionRunner-controller`:
   ```
   GET /api/v1/cluster/status
   ```
   Deployment proceeds only when:
   - `active_slots == 0` (no CI build or test stage is currently executing on target nodes).
   - `!exclusive_locked` (no node has an exclusive reservation active).
1. **TTL-Bounded Deployment Leases**:
   - `MuConDe-controller` submits an `AcquireLeaseRequest` specifying a bounded TTL (e.g., 300 seconds).
   - `ActionRunner-controller` grants an `AcquireLeaseResponse` locking CI stage dispatch to that node.
   - If the deployment finishes early, MuConDe explicitly releases the lease; if a node disconnects, the lease automatically expires safely.

______________________________________________________________________

## 4. Btrfs A/B Subvolume Architecture

Each managed service resides on a Btrfs filesystem under `/srv/muconde/<service>/`:

```
/srv/muconde/model-runner/
├── slot_a/         # Btrfs subvolume (@a, currently active)
│   └── bin/
│       └── model-runner (v0.3.4)
├── slot_b/         # Btrfs subvolume (@b, staging target)
│   └── bin/
│       └── model-runner (v0.3.5-rc.1)
└── current ──────► /srv/muconde/model-runner/slot_a
```

### Deployment Sequence:

1. **Identify Staging Slot**: The agent queries `/srv/muconde/<service>/current` symlink target. If `current` points to `slot_a`, the target staging slot is `slot_b` (and vice versa).
1. **Create Snapshot**: Creates a clean, read-write Btrfs subvolume snapshot:
   ```bash
   btrfs subvolume snapshot /srv/muconde/model-runner/slot_a /srv/muconde/model-runner/slot_b
   ```
1. **Unpack Binary**: Fetches the verified candidate tarball from MuRegist CAS and unpacks the binary into `/srv/muconde/<service>/slot_b/bin/`.
1. **Atomic Pointer Swap**:
   The symlink swap must be instantaneous and uninterrupted by system crashes:
   - Create a temporary symlink pointing to the new slot:
     `symlink("/srv/muconde/<service>/slot_b", "/srv/muconde/<service>/current.tmp")`
   - Atomically overwrite the active pointer via POSIX `rename()`:
     `rename("/srv/muconde/<service>/current.tmp", "/srv/muconde/<service>/current")`
1. **Service Signal**: Signals systemd to reload or restart the service unit:
   ```bash
   systemctl restart model-runner.service
   ```

______________________________________________________________________

## 5. Post-Swap Health Watchdog & Instant Rollback

Once the atomic pointer swap completes and the service is signaled, `MuConDe-agent` begins active watchdog monitoring over the configured `bake_window_secs` (e.g. 30 seconds).

### Watchdog Verification Checks

During each second of the bake window, the watchdog evaluates three criteria:

1. **Systemd Unit Status**: Queries D-Bus or `systemctl is-active`. If the state transitions to `failed`, `dead`, or `activating` (hung restart), watchdog triggers immediately.
1. **HTTP Health Probe**: Sends a `GET /healthz` request to the local probe port. Must return HTTP `200 OK` with JSON payload `{"status":"ready"}` within the configured timeout.
1. **IPC Ping Latency**: Issues an IPC handshake over Unix Domain Socket (`MuConDe-ipc`). Response latency must be below 50 ms.

### Instant Atomic Rollback (< 1s)

If any health check fails or times out during the bake window:

1. **Atomic Symlink Revert**:
   The agent immediately swaps `/srv/muconde/<service>/current` back to the previous stable slot (`slot_a`) using `symlink()` + `rename()` in under 5 ms.
1. **Immediate Service Restart**:
   Executes `systemctl restart <service>` to restore the proven, healthy version.
1. **Automatic MuRegist Candidate Tainting**:
   `MuConDe-controller` issues an authenticated API call to the MuRegist artifact registry:
   ```http
   POST /api/v1/canary/9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08/taint
   Authorization: Bearer <canary_admin_token>
   ```
   MuRegist marks the digest as `tainted`. This immediately halts rolling deployments to any other nodes in the cluster and notifies maintainers via alert webhooks.
