# Operator & Workflow Guide: Distributed `sccache` Compilation Caching

This guide walks cluster operators and workflow authors step-by-step through installing, configuring, verifying, and operating [`sccache`](https://github.com/mozilla/sccache) with **ActionRunner**, and explains how enabling `sccache` changes your day-to-day CI experience.

______________________________________________________________________

## 1. How `sccache` Influences Your Experience (What to Expect)

Before installing `sccache` on your cluster, it is critical to understand how compiler caching alters build timings, disk/network usage, scheduling, and failure modes across ActionRunner.

### 1.1 Default-On `try` Mode: What Happens the Moment You Install `sccache`

In ActionRunner, `sccache` policy defaults to **`try`** (`SccacheMode::Try`).

- **Before `sccache` is installed on a worker**:
  `WorkerConfig::detect_sccache_bin()` sees no `sccache` binary, does not advertise the `"sccache"` worker tag, and every pipeline in `try` mode runs normal, uncached `cargo` builds with zero errors.
- **The moment you install `/usr/local/bin/sccache` on a worker and restart `action-runner`**:
  The worker automatically detects the binary, appends `"sccache"` to its advertised capability `tags`, and **immediately begins caching all eligible Rust and WASM compilation tasks across every repository**—without requiring you to edit existing `.actionrunner/ActionRunner.yml` files!
- **How to opt out on a specific worker or workflow**:
  - **Per-worker opt-out**: Set `ACTION_RUNNER_SCCACHE_BIN=off` in `/etc/action-runner/worker.env`.
  - **Per-workflow, per-stage, or per-task opt-out**: Set `sccache: false` in `.actionrunner/ActionRunner.yml`.

### 1.2 Cold Cache vs. Warm Cache (Build #1 vs. Build #2+)

- **First Build (Cold Cache — 5% to 10% Slower)**:
  The first time a pipeline runs after installing `sccache` (or immediately after a Rust toolchain upgrade or `Cargo.lock` dependency update), `sccache` must compile every crate from scratch, hash all compiler inputs, compress the resulting `.rlib`/`.rmeta` artifacts, and write them to your storage backend.
  - **What you will see**: The first build will take slightly longer than an uncached build as it populates the cache. **This is expected.**
- **Subsequent Builds (Warm Cache — 60% to 85% Faster)**:
  On the next push or pull request, unchanged third-party dependencies and unmodified workspace crates bypass `rustc` codegen entirely and are fetched directly from the cache.
  - **What you will see**: `cargo-check`, `cargo-clippy`, `cargo-test`, and `cargo-build` stages finish in a fraction of their cold-build time.

### 1.3 Why `CARGO_INCREMENTAL=0` Is Automatically Enforced

Rust's built-in incremental compilation (`-C incremental=...`) relies on fine-grained local dependency graphs stored inside a single workspace's `target/debug/incremental` directory. Because those incremental query states are non-hermetic across directories and machines, `sccache` refuses to cache any `rustc` invocation with incremental compilation enabled.

- **How ActionRunner handles this**: Whenever `StageRunner` activates `sccache` for a task, it automatically injects `CARGO_INCREMENTAL=0` alongside `RUSTC_WRAPPER=<sccache_bin>`.
- **How this influences your experience**:
  - Each crate in your workspace is cached and recompiled as a whole unit rather than split into incremental sub-slices.
  - All upstream crate dependencies become 100% reusable cache hits across every branch, pull request, and worker node, while only the specific crate(s) modified in your commit are recompiled.
  - Your worker's `target/` directories consume significantly less disk space because `target/*/incremental/` directories are no longer generated.

### 1.4 Disk Space & Network Bandwidth Considerations

- **If you install `sccache` *without* `/etc/action-runner/sccache.env` (Local Disk Default)**:
  `sccache` automatically stores cached artifacts on the worker's local disk (`/var/lib/action-runner/.cache/sccache`, defaulting to a **`10 GiB`** LRU ceiling unless `SCCACHE_CACHE_SIZE` is configured). Ensure `/var/lib/action-runner` has at least `15–20 GiB` of free disk space.
- **If you configure `/etc/action-runner/sccache.env` with S3 / Garage / MinIO (Shared Cluster Cache)**:
  Compiled `.rlib` artifacts are uploaded and downloaded over HTTP(S) to your S3 endpoint (`SCCACHE_BUCKET`). During heavy parallel builds (`CARGO_BUILD_JOBS=6` or `8`), expect bursty LAN traffic between workers and your S3 server. Always deploy your S3/Garage cache server on the same low-latency local network as your worker nodes.

### 1.5 What Shares Cache Hits Across Worker Nodes (and What Does Not)

`sccache` computes its cache key from the **exact compiler binary digest**, **command-line flags**, **target triple**, and **preprocessed source inputs**:

1. **Mixed CPU Architectures (`x86_64` vs. `riscv64`)**:
   `x86_64` workers and `riscv64` workers can safely point to the **exact same `SCCACHE_BUCKET` and `SCCACHE_S3_KEY_PREFIX`** without collisions because the target triple is part of the hash. However, a native build on an `x86_64` worker only warms the cache for other `x86_64` builds, and a native build on a `riscv64` worker only warms the cache for other `riscv64` builds.
1. **Rust Toolchain Alignment Across Workers**:
   If `node-a` has `rustc 1.83.0` and `node-b` has `rustc 1.82.0`, their compiler binary digests differ and they will **never** share cache hits. Keep `/var/lib/action-runner/.rustup` synchronized across all workers of the same architecture (`sudo -u action-runner rustup update`).
1. **Workspace Path Consistency (`ACTION_RUNNER_WORKSPACE`)**:
   Keep `ACTION_RUNNER_WORKSPACE` (`/var/lib/action-runner/workspace`) identical across workers so path-dependent macros and debug symbols produce identical hashes across nodes.

### 1.6 Why Coverage (`cargo-llvm-cov`) and Miri (`cargo-miri`) Intentionally Bypass `sccache`

Operators often notice that `cargo-clippy` and `cargo-test` complete in seconds via `sccache`, whereas the `coverage` (`cargo-llvm-cov`) or `miri` (`cargo-miri`) stage compiles from scratch. This is intentional:

| Tool Adapter (`ActionRunner-tools`)                                                | `sccache` Applied? | Why / Operator Impact                                                                                                                                                                                                 |
| :--------------------------------------------------------------------------------- | :----------------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `cargo-build`, `cargo-check`, `cargo-test`, `cargo-clippy`, `cargo-bench`, `trunk` | **Yes (Eligible)** | Standard Rust and WASM compilation tools; receive `RUSTC_WRAPPER=<sccache_bin>`, `CARGO_INCREMENTAL=0`, `SCCACHE_IDLE_TIMEOUT=0`, and `sccache.env`.                                                                  |
| `cargo-llvm-cov`                                                                   | **No (Stripped)**  | Requires LLVM `-C instrument-coverage` instrumentation; wrapping with `sccache` can corrupt or bypass `.profraw` coverage counters. `StageRunner` explicitly removes `RUSTC_WRAPPER` and `CARGO_BUILD_RUSTC_WRAPPER`. |
| `cargo-miri`                                                                       | **No (Stripped)**  | Miri injects its own `RUSTC_WRAPPER` to interpret MIR; forcing `sccache` breaks Miri execution.                                                                                                                       |
| `cargo-fmt`, `cargo-audit`, `mdformat`, `git-checkout`                             | **No (Stripped)**  | Non-compiler hygiene and audit tools; `StageRunner` skips `sccache` so pure hygiene stages never require or invoke the cache daemon.                                                                                  |

### 1.7 Choosing Between `try`, `mandatory`, and `false`

You can configure `sccache` at the **workflow**, **stage**, or **task** level (`tasks.<id>.sccache -> stages[i].sccache -> workflow.sccache -> try`):

| Policy Value          | Accepted YAML Literals                | Scheduling Experience (`effective_stage_tags`)                                                                                                                                                              | Failure Experience on Worker                                                                                                                                                                     | When to Choose                                                                                                                      |
| :-------------------- | :------------------------------------ | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------- |
| **`try`** *(default)* | `try`, `true`, `auto`, `yes`, `1`     | Dispatches to **any** node matching the stage's `tags` (even nodes without `sccache`).                                                                                                                      | **Never breaks your build.** If `sccache` is missing or the S3 server is unreachable, the worker logs a warning, strips `RUSTC_WRAPPER`, and falls back cleanly to uncached `rustc` compilation. | Recommended default for 95% of stages: fast cached builds when healthy, zero CI downtime during cache maintenance.                  |
| **`mandatory`**       | `mandatory`, `required`, `strict`     | Automatically appends `"sccache"` to the stage's required capability `tags` (only dispatches to workers advertising `"sccache"`). **If no matching online worker has `sccache`, the stage stays `Queued`!** | **Fails closed (`exit_code = 126`)** before compiling if `sccache` is missing or fails its pre-flight `--show-stats` health check.                                                               | Heavy compilation stages on SBCs where an uncached cold build would take hours and you prefer fast failure over uncached execution. |
| **`false`**           | `false`, `off`, `disabled`, `no`, `0` | Dispatches to any node matching `tags`.                                                                                                                                                                     | Strips `RUSTC_WRAPPER` and `CARGO_BUILD_RUSTC_WRAPPER`; always compiles uncached.                                                                                                                | Compiler throughput benchmarks or isolating suspected cache issues.                                                                 |

______________________________________________________________________

## 2. How ActionRunner Manages the `sccache` Daemon Under the Hood

Understanding `sccache`'s client-daemon architecture explains how ActionRunner prevents the most common operational failures:

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Worker Node (systemd: action-runner-worker.service, User=action-runner) │
│                                                                         │
│  1. Startup: WorkerConfig::detect_sccache_bin() & load_sccache_env()    │
│     • Probes ACTION_RUNNER_SCCACHE_BIN, /usr/local/bin/sccache, etc.    │
│     • Reads /etc/action-runner/sccache.env                              │
│     • Strips RUSTC_WRAPPER / CARGO_BUILD_RUSTC_WRAPPER for safety       │
│     • Appends "sccache" to WorkerRegistration.tags                      │
│                                                                         │
│  2. Pre-Stage Health Gate: StageRunner::ensure_sccache_server_healthy() │
│     • Runs `sccache --show-stats` (5s timeout) with sccache.env         │
│     • Detects "Local disk" hijack when SCCACHE_BUCKET is set ──►        │
│       auto-runs `--stop-server` + `--show-stats` with S3 env            │
│     • Single retry (`--stop-server` + `--show-stats`) if socket wedged  │
│                                                                         │
│  3. Task Execution (Inside MuIsolation Sandbox)                         │
│     • Eligible tool (e.g. cargo-clippy) gets RUSTC_WRAPPER=<bin>,       │
│       CARGO_INCREMENTAL=0, SCCACHE_IDLE_TIMEOUT=0, and sccache.env      │
│     • Thin `sccache` client connects to local daemon (127.0.0.1:4226)   │
│     • Persistent daemon communicates with S3 / Local Disk cache         │
└─────────────────────────────────────────────────────────────────────────┘
```

- **Why the "Local Disk Hijack" Happens (and How ActionRunner Automatically Heals It)**:
  `sccache` uses a background daemon listening on `127.0.0.1:4226`. Whichever process invokes `sccache` *first* spawns that background daemon, and **all environment variables on later `sccache` client commands are ignored as long as that daemon stays running**.
  If an operator SSHes into a worker when the daemon is stopped and runs `sudo -u action-runner sccache --show-stats` *without* sourcing `/etc/action-runner/sccache.env` first, `sccache` silently spawns a background daemon in **`Local disk` mode**—causing subsequent builds to ignore your S3 bucket!
  To protect operators from this trap, `StageRunner::ensure_sccache_server_healthy` inspects the `Cache location` line of `sccache --show-stats` before every stage. If `SCCACHE_BUCKET` is configured in `/etc/action-runner/sccache.env` but the daemon reports `Cache location: Local disk`, ActionRunner automatically runs `sccache --stop-server` and restarts the daemon with your S3 credentials.

______________________________________________________________________

## 3. Step-by-Step Operator Installation Guide

Follow these steps on each worker node where you want `sccache` acceleration.

### Step 1: Install the `sccache` Binary to `/usr/local/bin/sccache`

> **Critical Service Account & Sandbox Rule**: Never install `sccache` only inside `/root/.cargo/bin` or a personal `/home/<user>/.cargo/bin` directory. `action-runner` runs under the isolated `action-runner` service account with `ProtectHome=read-only` and `MuIsolation` Landlock rules that restrict execution to `/usr/local/bin`, `/usr/bin`, `/bin`, and `/var/lib/action-runner/.cargo/bin`. Always install `sccache` to **`/usr/local/bin/sccache`** (`0755 root:root`).

#### Option A: `x86_64` or `aarch64` Linux Worker (Official Prebuilt Binary)

```bash
SCCACHE_VERSION="v0.8.2"
ARCH="$(uname -m)" # x86_64 or aarch64
curl -fL "https://github.com/mozilla/sccache/releases/download/${SCCACHE_VERSION}/sccache-${SCCACHE_VERSION}-${ARCH}-unknown-linux-musl.tar.gz" -o /tmp/sccache.tar.gz
tar -xzf /tmp/sccache.tar.gz -C /tmp
sudo install -m 755 "/tmp/sccache-${SCCACHE_VERSION}-${ARCH}-unknown-linux-musl/sccache" /usr/local/bin/sccache
rm -rf /tmp/sccache.tar.gz "/tmp/sccache-${SCCACHE_VERSION}-${ARCH}-unknown-linux-musl"
```

#### Option B: `riscv64` (SpacemiT K3) or Custom Linux Worker (Build from Source)

On `riscv64gc-unknown-linux-gnu` nodes, build `sccache` natively using the worker's Rust toolchain and install the resulting binary into `/usr/local/bin/sccache`:

```bash
# 1. Install build prerequisites (Debian/Ubuntu/Bianbu)
sudo apt-get update && sudo apt-get install -y pkg-config libssl-dev build-essential

# 2. Compile sccache using the action-runner service account toolchain
sudo -u action-runner env \
  RUSTUP_HOME=/var/lib/action-runner/.rustup \
  CARGO_HOME=/var/lib/action-runner/.cargo \
  PATH="/var/lib/action-runner/.cargo/bin:/usr/local/bin:/usr/bin:/bin" \
  cargo install sccache --locked

# 3. Install into /usr/local/bin so all sandbox profiles can execute it
sudo install -m 755 /var/lib/action-runner/.cargo/bin/sccache /usr/local/bin/sccache
```

Verify that the `action-runner` service account can execute the binary:

```bash
sudo -u action-runner /usr/local/bin/sccache --version
```

______________________________________________________________________

### Step 2: Choose and Configure Your Cache Backend (`/etc/action-runner/sccache.env`)

`WorkerConfig::load_sccache_env()` automatically reads `/etc/action-runner/sccache.env` (or the path set in `ACTION_RUNNER_SCCACHE_ENV_FILE`). First, ensure `/etc/action-runner` is owned and traversable by the `action-runner` service account (`0700 action-runner:action-runner`, **not** `0700 root:root`):

```bash
sudo install -d -m 700 -o action-runner -g action-runner /etc/action-runner
```

Now choose **Backend Option 1 (Local Disk)** or **Backend Option 2 (Shared S3 / Garage / MinIO)**:

#### Backend Option 1: Per-Node Local Disk Cache (Simplest Setup — Zero External Services)

Use this option if you have a single worker node per architecture or want each worker to store cached artifacts on its own local NVMe/SSD.

1. Create the cache directory under `/var/lib/action-runner`:
   ```bash
   sudo install -d -m 750 -o action-runner -g action-runner /var/lib/action-runner/.cache/sccache
   ```
1. Write `/etc/action-runner/sccache.env`:
   ```bash
   sudo tee /etc/action-runner/sccache.env >/dev/null <<'EOF'
   # Local Disk Cache Configuration
   SCCACHE_DIR=/var/lib/action-runner/.cache/sccache
   SCCACHE_CACHE_SIZE=20G
   SCCACHE_SERVER_PORT=4226
   SCCACHE_IDLE_TIMEOUT=0
   EOF
   sudo chown action-runner:action-runner /etc/action-runner/sccache.env
   sudo chmod 600 /etc/action-runner/sccache.env
   ```

#### Backend Option 2: Multi-Node Shared S3 Cache (Garage / MinIO / AWS S3)

Use this option when multiple workers share the same architecture so a crate compiled on one node is immediately available as a cache hit on all other nodes.

1. Create a bucket (for example `sccache`) and a read/write access key on your S3-compatible server (such as [Garage](https://garagehq.deuxfleurs.fr/), MinIO, Ceph RGW, or AWS S3).
1. Write `/etc/action-runner/sccache.env`:
   ```bash
   sudo tee /etc/action-runner/sccache.env >/dev/null <<'EOF'
   # Shared S3-Compatible Cache Configuration (Garage / MinIO / AWS S3)
   SCCACHE_BUCKET=sccache
   SCCACHE_REGION=us-east-1
   SCCACHE_ENDPOINT=http://192.0.2.10:3900
   SCCACHE_S3_USE_SSL=false
   SCCACHE_S3_KEY_PREFIX=v1/
   SCCACHE_SERVER_PORT=4226
   SCCACHE_IDLE_TIMEOUT=0
   AWS_ACCESS_KEY_ID=GK0123456789abcdef01234567
   AWS_SECRET_ACCESS_KEY=replace-with-your-s3-secret-key
   EOF
   sudo chown action-runner:action-runner /etc/action-runner/sccache.env
   sudo chmod 600 /etc/action-runner/sccache.env
   ```

> **Configuration Notes**:
>
> - **`SCCACHE_IDLE_TIMEOUT=0`**: Keeps the local `sccache` daemon alive indefinitely so it never shuts down mid-stage during long linking steps (`StageRunner` also enforces `0` by default if omitted).
> - **`SCCACHE_S3_KEY_PREFIX`**: Optional prefix (must end with `/`) allowing you to namespace or rotate cache epochs across the cluster without deleting the bucket.
> - **Do not set `RUSTC_WRAPPER` in `sccache.env`**: `WorkerConfig::load_sccache_env()` automatically strips `RUSTC_WRAPPER` and `CARGO_BUILD_RUSTC_WRAPPER` so that non-eligible tools (`cargo-llvm-cov`, `cargo-miri`, `cargo-audit`, `cargo-fmt`) are never accidentally wrapped.

______________________________________________________________________

### Step 3: Verify `MuIsolation` Sandbox (`.actionrunner/security.yml`) & Systemd Grants

1. **Systemd Service (`action-runner-worker.service`)**:
   Ensure `/var/lib/action-runner` and `/tmp` are writable when `ProtectSystem=strict` is enabled, and `/etc/action-runner` is readable by `User=action-runner`.
1. **Repository Sandbox Profile (`.actionrunner/security.yml`)**:
   Ensure `read_paths` includes `/usr` and `exec_paths` includes `/usr/local/bin` and `/usr/bin` so Landlock permits `cargo` to execute `/usr/local/bin/sccache`:
   ```yaml
   default_profile: "default_ci"
   profiles:
     default_ci:
       backend: Kernel
       read_paths:
         - "/usr"
         - "/bin"
         - "/lib"
         - "/etc/ssl"
         - "/var/lib/action-runner"
       write_paths:
         - "/var/lib/action-runner"
         - "/tmp"
       exec_paths:
         - "/usr/bin"
         - "/usr/local/bin"
         - "/bin"
         - "/var/lib/action-runner/.cargo/bin"
         - "/var/lib/action-runner/.rustup"
         - "/var/lib/action-runner/.local/bin"
   ```

______________________________________________________________________

### Step 4: Test the Daemon & Restart the Worker Service

Before restarting the worker service, test starting the `sccache` daemon directly under the `action-runner` user with `/etc/action-runner/sccache.env` loaded:

```bash
sudo -u action-runner bash -c '
  set -a
  source /etc/action-runner/sccache.env
  set +a
  /usr/local/bin/sccache --stop-server >/dev/null 2>&1 || true
  /usr/local/bin/sccache --start-server
  /usr/local/bin/sccache --show-stats
'
```

Inspect the `Cache location` line in the output:

- For **Local Disk**, it must display:
  `Cache location    Local disk: "/var/lib/action-runner/.cache/sccache"`
- For **S3 / Garage / MinIO**, it must display:
  `Cache location    S3, bucket: Bucket(name=sccache), key_prefix: v1/`

Now restart the worker daemon so it detects `/usr/local/bin/sccache`, loads `/etc/action-runner/sccache.env`, and advertises `"sccache"` in its registration tags:

```bash
sudo systemctl restart action-runner-worker
```

______________________________________________________________________

## 4. End-to-End Verification Walkthrough

Complete these three checks after restarting your worker to confirm everything is working end-to-end:

### Check 1: Confirm Controller Capability Advertisement

Query the controller's cluster nodes API and confirm `"sccache"` appears inside `tags` for your worker node:

```bash
curl -s http://192.0.2.10:8000/api/cluster/nodes | jq '.[] | {node_id, status, tags}'
```

Expected output:

```json
{
  "node_id": "worker-riscv64",
  "status": "online",
  "tags": [
    "riscv64",
    "linux",
    "clippy",
    "test",
    "build",
    "sccache"
  ]
}
```

### Check 2: Trigger Build #1 (Cold Cache) and Inspect Live Stats

Trigger a CI run on any Rust repository (remember `sccache: try` is active by default even if not explicitly written in `.actionrunner/ActionRunner.yml`). Once a compilation stage (`clippy` or `test`) finishes, run the stats check on the worker node:

```bash
sudo -u action-runner bash -c 'set -a && source /etc/action-runner/sccache.env && set +a && /usr/local/bin/sccache --show-stats'
```

On **Build #1 (Cold Cache)**, verify that:

- `Compile requests` > `0`
- `Cache misses` > `0` (artifacts are being compiled and uploaded to the cache)
- `Cache write errors` == `0`

### Check 3: Trigger Build #2 (Warm Cache)

Re-trigger the pipeline or open a pull request with a small leaf change, then run `--show-stats` again:

- `Cache hits` increases sharply (`70%–95%+` of cacheable requests)
- Stage wall-clock duration drops by `60%–85%`

______________________________________________________________________

## 5. Operator Troubleshooting & FAQ

### Q1: Why did `sccache --show-stats` revert to `Local disk` after I checked it manually via SSH?

**Cause**: You ran `sudo -u action-runner sccache --show-stats` when the daemon was stopped, **without** sourcing `/etc/action-runner/sccache.env` first. That command auto-spawned a new background daemon with empty environment variables (defaulting to `Local disk`).
**Fix**: Always inspect stats using:

```bash
sudo -u action-runner bash -c 'set -a && source /etc/action-runner/sccache.env && set +a && /usr/local/bin/sccache --show-stats'
```

*(Note: `StageRunner::ensure_sccache_server_healthy` also detects and heals this automatically at the start of the next CI stage.)*

### Q2: Why is my stage with `sccache: mandatory` stuck in `Queued` forever?

**Cause**: When a stage resolves to `mandatory`, `ActionRunnerWorkflow::effective_stage_tags` appends `"sccache"` to the stage's required worker capability tags. No online worker matching your stage's other `tags` (e.g. `riscv64`, `build`) currently advertises `"sccache"`.
**Fix**: Check `GET /api/cluster/nodes` on the controller. Either install `/usr/local/bin/sccache` and restart the worker service on a matching node, or change the workflow/stage/task policy to `sccache: try` so the stage can run uncached when no `sccache`-capable worker is online.

### Q3: Why did my stage fail immediately with `exit code 126` (`sccache mandatory policy failed`)?

**Cause**: Your stage is configured with `sccache: mandatory`, and `StageRunner::ensure_sccache_server_healthy` failed to start or verify the `sccache` daemon on the worker (typically due to an unreachable S3 endpoint, invalid S3 credentials, or permission denied on `/etc/action-runner/sccache.env`).
**Fix**: Run the Step 4 diagnostic command on the worker with `SCCACHE_LOG=debug` to inspect the exact S3 or filesystem error:

```bash
sudo -u action-runner bash -c 'set -a && source /etc/action-runner/sccache.env && set +a && /usr/local/bin/sccache --stop-server ; SCCACHE_LOG=debug /usr/local/bin/sccache --start-server'
```

### Q4: Why are cache hit rates `0%` even though `sccache --show-stats` shows `S3`?

**Cause**: Check `Cache write errors` and `Non-cacheable compilations` in `sccache --show-stats`:

- If `Cache write errors > 0`, the access key in `/etc/action-runner/sccache.env` lacks write permission to the bucket or the bucket quota is full.
- If `Cache hits` is `0` across two different worker nodes of the same architecture, verify both workers have the exact same Rust toolchain version (`sudo -u action-runner rustup show`) and identical `ACTION_RUNNER_WORKSPACE` paths.
