# Declarative .actionrunner/ActionRunner.yml Syntax Reference

This guide provides the complete specification for the declarative **Version 3** configuration schema (`.actionrunner/ActionRunner.yml`) utilized by the ActionRunner continuous integration and verification engine.

______________________________________________________________________

## 1. Architectural Overview & 3-Tier Model

Version 3 replaces legacy, fragmented event files (`.actionrunner/on-*.yml`) with a single, unified declarative pipeline contract. The schema decouples execution logic into three distinct tiers:

1. **Tier 1 (`tasks`)**: Atomic command definitions backed by the compile-time `ToolAdapter` registry. Tasks specify strict argument arrays with no shell interpretation.
1. **Tier 2 (`stages`)**: A Directed Acyclic Graph (DAG) of execution stages. Stages orchestrate task sequences, declare dependencies (`depends_on`), constrain thread budgets, require target node tags, and enforce hardware exclusivity.
1. **Tier 3 (`on_action`)**: Event trigger bindings that map inbound Git and webhook events (`push`, `pull_request`, `merge`, `tag`) to terminal target stages in the DAG.

```
┌──────────────────────────────────────────────────────────────────┐
│                   Tier 3: on_action Triggers                     │
│           push ──────► pull_request ──────► merge / tag          │
└─────────────────────────────────┬────────────────────────────────┘
                                  │ Resolves Target Stages
                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│                     Tier 2: stages (DAG Engine)                  │
│       ┌──────────────┐     ┌──────────────┐     ┌──────────────┐ │
│       │  Stage: fmt  │ ──► │ Stage: clippy│ ──► │ Stage: test  │ │
│       └──────────────┘     └──────────────┘     └──────────────┘ │
└─────────────────────────────────┬────────────────────────────────┘
                                  │ Executes In-Order
                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│                     Tier 1: tasks (Tool Adapters)                │
│       cargo-fmt, cargo-clippy, cargo-test, cargo-llvm-cov ...    │
└──────────────────────────────────────────────────────────────────┘
```

______________________________________________________________________

## 2. Top-Level Specification

A valid `.actionrunner/ActionRunner.yml` document must contain the following top-level keys:

```yaml
version: "3"
name: "my-project-ci"
env:
  RUST_BACKTRACE: "1"
tasks:
  # Map of task definitions (Tier 1)
stages:
  # List of stage definitions (Tier 2)
on_action:
  # Map of event triggers (Tier 3)
```

### Top-Level Fields

| Field       | Type   | Required | Description                                                        |
| :---------- | :----- | :------- | :----------------------------------------------------------------- |
| `version`   | string | **Yes**  | Schema version. Must be exactly `"3"`.                             |
| `name`      | string | **Yes**  | Human-readable name for the pipeline.                              |
| `env`       | map    | No       | Global environment variable key-value pairs exported to all tasks. |
| `tasks`     | map    | **Yes**  | Map of unique task IDs to `TaskSpec` definitions.                  |
| `stages`    | list   | **Yes**  | List of `StageSpec` definitions forming the execution DAG.         |
| `on_action` | map    | **Yes**  | Map of webhook action triggers to lists of target stage IDs.       |

______________________________________________________________________

## 3. Tier 1: Task Specifications (`tasks`)

The `tasks` map defines reusable atomic commands executed by ActionRunner workers.

### Task Fields (`TaskSpec`)

```yaml
tasks:
  lint-cargo:
    tool: "cargo-clippy"
    args: ["--workspace", "--all-targets", "--", "-D", "warnings"]
    working_dir: "code/core"
    env:
      CARGO_TERM_COLOR: "always"
    timeout_seconds: 300
    sandbox_profile: "strict"
```

| Field             | Type    | Required | Description                                                                        |
| :---------------- | :------ | :------- | :--------------------------------------------------------------------------------- |
| `tool`            | string  | **Yes**  | Tool identifier registered in the compile-time `ToolAdapter` registry.             |
| `args`            | list    | No       | Explicit list of string arguments passed directly to the binary. Defaults to `[]`. |
| `working_dir`     | string  | No       | Relative directory within the repository workspace. Defaults to repository root.   |
| `env`             | map     | No       | Task-specific environment variable overrides.                                      |
| `timeout_seconds` | integer | No       | Maximum execution duration before SIGTERM/SIGKILL. Defaults to `600`.              |
| `sandbox_profile` | string  | No       | Name of the desired sandbox profile matching `.actionrunner/security.yml`.         |

### Compile-Time `ToolAdapter` Registry

ActionRunner invokes commands through a typed Rust `ToolAdapter` registry (`ActionRunner-tools`). Supported tools include:

- `cargo-fmt`: Invokes `cargo fmt` with formatting verification (`--check`).
- `cargo-clippy`: Invokes `cargo clippy` with workspace linting flags.
- `cargo-check`: Runs compilation checks across target architectures.
- `cargo-test`: Runs unit and integration test harnesses.
- `cargo-build`: Builds release or debug binaries and shared libraries.
- `cargo-doc`: Generates documentation and validates doc-tests.
- `cargo-audit`: Scans dependencies for security vulnerabilities against `advisory-db`.
- `cargo-llvm-cov`: Computes source-based code coverage summaries.
- `cargo-miri`: Executes test suites under Miri undefined-behavior detection.
- `git-checkout`: Synchronizes Git trees, commits, and submodules.
- `mdformat`: Formats and checks CommonMark and GitHub Flavored Markdown (GFM) documents.

### Strict Shell Metacharacter & `bash -c` Prohibition

To prevent arbitrary code execution, privilege escalation, and non-deterministic pipeline side effects, ActionRunner disallows raw shell invocation:

- **No Shell Interpreters**: Tools are executed via direct `execve`-style calls (`std::process::Command::args`). Passing `bash`, `sh`, `zsh`, `eval`, or `exec` in `tool` or `args` triggers a `ProhibitedShellInvocation` error during manifest parsing.
- **Forbidden Metacharacters**: Task arguments must not contain shell redirection or piping operators:
  - Command chaining: `;`, `&&`, `||`
  - Redirection: `>`, `>>`, `<`, `<<`, `|`
  - Subshells & substitution: `$(...)`, `` `...` ``, `${...}`
  - Background operators: `&`
- Any task definition containing forbidden tokens is rejected before worker dispatch.

______________________________________________________________________

## 4. Tier 2: Stages & DAG Execution Engine (`stages`)

The `stages` list defines the topological execution graph. Stages group tasks, declare dependencies, and set hardware constraints.

### Stage Fields (`StageSpec`)

```yaml
stages:
  - id: "unit-tests"
    name: "Run Core Unit Tests"
    tasks: ["test-core", "test-engine"]
    depends_on: ["lint", "type-check"]
    tags: ["worker-riscv64", "ci-runner"]
    threads: 6
    toolchain: "stable"
    exclusive: false
    max_concurrent_per_node: 1
```

| Field                     | Type    | Required | Description                                                                    |
| :------------------------ | :------ | :------- | :----------------------------------------------------------------------------- |
| `id`                      | string  | **Yes**  | Unique identifier for the stage across the pipeline.                           |
| `name`                    | string  | **Yes**  | Human-readable stage description for logs and status cards.                    |
| `tasks`                   | list    | **Yes**  | Ordered list of task IDs from Tier 1 executed sequentially in this stage.      |
| `depends_on`              | list    | No       | List of prerequisite stage IDs that must succeed before this stage starts.     |
| `tags`                    | list    | No       | Capability tags required on worker nodes (e.g. `riscv64`, `x86_64`, `vector`). |
| `threads`                 | integer | No       | Thread budget allocated to this stage. Defaults to `2`.                        |
| `toolchain`               | string  | No       | Rust toolchain selector (`stable`, `nightly`, `beta`). Defaults to `stable`.   |
| `exclusive`               | boolean | No       | When `true`, demands full-node serialization/drain. Defaults to `false`.       |
| `max_concurrent_per_node` | integer | No       | Concurrency limit per worker node. Enforced at `1`.                            |

### DAG Validation & Cycle Detection

During pipeline ingestion, ActionRunner converts the `stages` list into an adjacency matrix and runs topological sorting (Kahn's algorithm with depth-first search verification):

- **Acyclic Enforcement**: If a circular dependency is detected (e.g. `A -> B -> C -> A`), validation fails immediately with `CycleDetected` referencing the cyclic node path.
- **Missing Dependency**: Referencing a stage in `depends_on` that does not exist produces a `StageNotFound` validation error.
- **Deterministic Scheduling**: Independent stages execute concurrently across separate nodes matching worker tags.

### Single-Slot Worker Invariant (`max_concurrent_per_node: 1`)

ActionRunner worker nodes enforce a strict single-stage execution slot:

- `max_concurrent_per_node: 1` ensures at most **one** active CI stage process runs on a physical node at any time, preventing cache thrashing and memory exhaustion.
- While individual nodes enforce `max_slots = 1`, stages without mutual dependencies run in parallel across distinct nodes in the cluster.
- `exclusive: true` enforces full-node draining: all background tasks and pending allocations on the worker must completely vacate before the exclusive stage begins (useful for microbenchmarks or hardware vector validation).

### Thread Budget Environment Mapping

The `threads` integer bounds parallel compiler and test runner jobs by automatically exporting:

- `CARGO_BUILD_JOBS=<threads>`
- `RAYON_NUM_THREADS=<threads>`
- `RUST_TEST_THREADS=<threads>`

______________________________________________________________________

## 5. Tier 3: Action Triggers (`on_action`)

The `on_action` block binds inbound Git and webhook events to target stages in the DAG.

```yaml
on_action:
  push:
    stages: ["lint", "unit-tests"]
  pull_request:
    stages: ["lint", "unit-tests", "coverage"]
  merge:
    stages: ["lint", "unit-tests", "coverage", "benchmark", "publish-check"]
  tag:
    stages: ["release-build", "publish-muregist"]
```

### Event Resolution Semantics

When an event triggers:

1. ActionRunner identifies the target stages specified under the matching event key.
1. The scheduler computes the **backwards transitive closure** in the DAG: all prerequisite stages declared via `depends_on` are automatically enqueued in valid topological order.
1. Stages that are not reachable from the requested targets are pruned from the execution run.

______________________________________________________________________

## 6. Three-Phase Configuration Migration

To safely transition production repositories from legacy `.actionrunner/on-*.yml` files without downtime, teams follow a strict 3-phase rollout:

```
┌────────────────────────────────────────────────────────────────────────┐
│ Phase 1: Dual-Stack Fallback                                           │
│ ActionRunner.yml takes precedence. If absent, fallback to on-*.yml.    │
│ Logs: legacy_workflow_loaded. Metric: actionrunner_legacy_workflow_... │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Production cutover verified
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Phase 2: Production Verification & Legacy Disable                      │
│ Set ACTIONRUNNER_DISABLE_LEGACY=1 on controllers.                      │
│ Legacy on-*.yml files are strictly rejected with ConfigurationError.   │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Repository cleanup
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Phase 3: Post-Deployment Legacy Removal                                │
│ Delete obsolete on-*.yml files from repositories.                      │
│ Remove legacy fallback parsers from daemon source code.                │
└────────────────────────────────────────────────────────────────────────┘
```

1. **Phase 1: Side-by-Side Dual-Stack Fallback**:
   - The daemon checks for `.actionrunner/ActionRunner.yml`. If found, it parses and executes the Tier 3 pipeline.
   - If missing, the controller emits a structured warning (`legacy_workflow_loaded`) and increments the Prometheus counter `actionrunner_legacy_workflow_loads_total{repository="..."}` while falling back to legacy `on-*.yml`.
1. **Phase 2: Production Cutover**:
   - All services deploy `.actionrunner/ActionRunner.yml`.
   - Controllers enable `ACTIONRUNNER_DISABLE_LEGACY=1`. Attempts to run legacy workflows fail closed with an admission rejection.
1. **Phase 3: Clean-Up & Retirement**:
   - Legacy files (`.actionrunner/on-push.yml`, `.actionrunner/on-pullrequest.yml`, `.actionrunner/on-merge.yml`) are removed from repositories.
   - Legacy parser code is permanently pruned from the `ActionRunner-controller` codebase.

______________________________________________________________________

## 7. Annotated Example

Below is a complete, production-grade `.actionrunner/ActionRunner.yml` pipeline:

```yaml
version: "3"
name: "k3-platform-ci"

env:
  RUST_BACKTRACE: "1"
  CARGO_INCREMENTAL: "0"

tasks:
  format-check:
    tool: "cargo-fmt"
    args: ["--all", "--", "--check"]
    timeout_seconds: 120

  markdown-check:
    tool: "mdformat"
    args: ["--check", "content/", "ReadMe.md"]
    timeout_seconds: 60

  clippy-lint:
    tool: "cargo-clippy"
    args: ["--workspace", "--all-targets", "--", "-D", "warnings"]
    env:
      CARGO_TERM_COLOR: "always"
    timeout_seconds: 300
    sandbox_profile: "strict"

  audit-dependencies:
    tool: "cargo-audit"
    args: ["audit"]
    timeout_seconds: 180

  test-workspace:
    tool: "cargo-test"
    args: ["--workspace", "--tests"]
    timeout_seconds: 600
    sandbox_profile: "standard"

  coverage-report:
    tool: "cargo-llvm-cov"
    args: ["--workspace", "--lcov", "--output-path", "target/lcov.info"]
    timeout_seconds: 900
    sandbox_profile: "standard"

  benchmark-vector:
    tool: "cargo-test"
    args: ["--bench", "kernel_benchmarks"]
    timeout_seconds: 1200
    sandbox_profile: "hardware-vector"

stages:
  - id: "formatting"
    name: "Source Code & Documentation Formatting"
    tasks: ["format-check", "markdown-check"]
    tags: ["ci-runner"]
    threads: 2
    toolchain: "stable"
    exclusive: false
    max_concurrent_per_node: 1

  - id: "linting"
    name: "Static Analysis & Clippy Lints"
    tasks: ["clippy-lint", "audit-dependencies"]
    depends_on: ["formatting"]
    tags: ["ci-runner"]
    threads: 4
    toolchain: "stable"
    exclusive: false
    max_concurrent_per_node: 1

  - id: "unit-tests"
    name: "Workspace Unit Tests"
    tasks: ["test-workspace"]
    depends_on: ["linting"]
    tags: ["worker-riscv64"]
    threads: 6
    toolchain: "stable"
    exclusive: false
    max_concurrent_per_node: 1

  - id: "coverage"
    name: "LLVM Source-Based Code Coverage"
    tasks: ["coverage-report"]
    depends_on: ["unit-tests"]
    tags: ["worker-riscv64"]
    threads: 6
    toolchain: "nightly"
    exclusive: false
    max_concurrent_per_node: 1

  - id: "benchmarks"
    name: "Hardware-Exclusive Vector Benchmarks"
    tasks: ["benchmark-vector"]
    depends_on: ["unit-tests"]
    tags: ["worker-riscv64", "vector"]
    threads: 6
    toolchain: "nightly"
    exclusive: true
    max_concurrent_per_node: 1

on_action:
  push:
    stages: ["formatting", "linting", "unit-tests"]
  pull_request:
    stages: ["coverage"]
  merge:
    stages: ["coverage", "benchmarks"]
```
