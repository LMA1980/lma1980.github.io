# MuRegist Cargo Sparse Registry & Artifact Store Developer Guide

This guide details the architecture, client configuration, and API specifications for **MuRegist** (`AGPL-3.0-only`), the high-performance internal Cargo Sparse HTTP Registry and multi-ecosystem artifact repository.

______________________________________________________________________

## 1. Architectural Overview

MuRegist provides private package indexing and content-addressed storage (CAS) optimized for distributed compiler workloads and automated CI/CD pipelines.

Key capabilities include:

1. **RFC 2789 Cargo Sparse Index**: On-demand HTTP package index retrieval, eliminating the requirement to clone massive Git index repositories.
1. **SHA-256 Content-Addressed Store (CAS)**: Immutable, deduped tarball storage with atomic commit verification.
1. **Parameterized DuckDB Catalog**: High-throughput embedded relational metadata catalog managing crate versions, dependency graphs, and release states without SQLite write locks.
1. **Staged Canary & Test Promotion API**: Pre-publication staging pipeline allowing candidate tarballs to be validated against integration test suites before public index promotion.
1. **Mutual TLS & Scoped Bearer Tokens**: Cryptographically authenticated endpoints backed by automated `step-ca` certificates and Argon2id-hashed bearer tokens.

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Developer / CI Client                           │
│     cargo fetch / cargo publish ──► TLS + Scoped Bearer Token          │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ HTTPS (Port 8444)
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                     MuRegist Server Architecture                       │
│                                                                        │
│   ┌────────────────────────────────┐  ┌────────────────────────────┐   │
│   │   Sparse Index Protocol        │  │  Canary & Promotion Engine │   │
│   │   GET /index/... (RFC 2789)    │  │  /api/v1/canary/...        │   │
│   └───────────────┬────────────────┘  └─────────────┬──────────────┘   │
│                   │                                 │                  │
│                   ▼                                 ▼                  │
│   ┌────────────────────────────────┐  ┌────────────────────────────┐   │
│   │ Content-Addressed Store (CAS)  │  │   DuckDB Metadata Catalog  │   │
│   │ blobs/sha256/aa/bb/<hash>      │  │   muregist.duckdb          │   │
│   └────────────────────────────────┘  └────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────┘
```

______________________________________________________________________

## 2. Cargo Sparse Index Protocol (RFC 2789)

MuRegist implements the official Cargo Sparse HTTP Index specification. Instead of downloading a full Git repository, Cargo fetches only the specific endpoint corresponding to the crate name.

### Index Endpoints

| Endpoint                        | Description                                                | Example Crate                       |
| :------------------------------ | :--------------------------------------------------------- | :---------------------------------- |
| `GET /index/config.json`        | Registry configuration defining download and API endpoints | N/A                                 |
| `GET /index/1/{crate}`          | 1-letter crates                                            | `GET /index/1/a`                    |
| `GET /index/2/{crate}`          | 2-letter crates                                            | `GET /index/2/io`                   |
| `GET /index/3/{prefix}/{crate}` | 3-letter crates (prefixed by 1st letter)                   | `GET /index/3/k/k3c`                |
| `GET /index/{p1}/{p2}/{crate}`  | 4+ letter crates (prefixed by 1st two pairs)               | `GET /index/ac/ti/actionrunner-ipc` |

### `config.json` Specification

Cargo requests `/index/config.json` to discover the download URL template and API base:

```json
{
  "dl": "https://registry.ci.ci.internal:8444/api/v1/crates/{crate}/{version}/download",
  "api": "https://registry.ci.ci.internal:8444"
}
```

### Crate Index Entry Format

Each crate endpoint returns newline-delimited JSON (NDJSON) records. Each line represents a released semantic version:

```json
{"name":"k3-core","vers":"0.2.0","deps":[],"cksum":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855","features":{},"yanked":false}
{"name":"k3-core","vers":"0.3.0","deps":[],"cksum":"9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08","features":{"rvv":["k3-kernels-rvv"]},"yanked":false}
```

______________________________________________________________________

## 3. Client Configuration & Publishing

### Step 1: Configure Cargo Registry (`.cargo/config.toml`)

In your repository or global user configuration (`~/.cargo/config.toml`), declare the sparse registry:

```toml
[registries.muregist]
index = "sparse+https://registry.ci.ci.internal:8444/index/"

# Default to internal registry for local builds
[registry]
default = "muregist"
```

### Step 2: Authentication Credentials (`~/.cargo/credentials.toml`)

Authentication requires an Argon2id-hashed bearer token issued by the administrator or CI secret store:

```toml
[registries.muregist]
token = "muregist_sec_9a8f23e71d44bc0991e2f6a89c"
```

### Step 3: Publish Crate

Publishing packages to MuRegist is performed directly with the standard Cargo CLI:

```bash
cargo publish --registry muregist
```

#### Binary Multipart Upload Framing (`PUT /api/v1/crates/new`)

When `cargo publish` executes, Cargo uploads the crate payload via an RFC-compliant binary multipart packet over HTTPS:

1. **Header Block 1 (4 bytes, Little-Endian `u32`)**: Length $L\_{\\text{json}}$ of the metadata JSON string.
1. **Metadata JSON String**: UTF-8 encoded JSON object declaring package name, version, dependencies, and feature flags.
1. **Header Block 2 (4 bytes, Little-Endian `u32`)**: Length $L\_{\\text{crate}}$ of the binary `.crate` tarball.
1. **Crate Tarball**: Gzipped `.tar.gz` archive containing source files and `Cargo.toml`.

MuRegist validates the framing, extracts the tarball, checks licensing metadata, computes the SHA-256 digest, and atomically commits the asset to the CAS.

______________________________________________________________________

## 4. Content-Addressed Store (CAS) & DuckDB Catalog

### CAS Storage Layout

Binary crate archives and integration bundles are stored in a two-tier fan-out directory structure keyed by the SHA-256 digest:

```
/var/lib/muregist/storage/
└── blobs/
    └── sha256/
        ├── 9f/
        │   └── 86/
        │       └── 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08
        └── e3/
            └── b0/
                └── e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
```

### Atomic Commit Invariant

To guarantee data integrity during concurrent CI publishing:

1. The server streams the inbound stream to a unique temporary file on the same filesystem:
   `/var/lib/muregist/storage/tmp/.upload.<uuid>`
1. While streaming, the server updates an incremental SHA-256 hasher.
1. Once stream EOF is reached, the server verifies the computed checksum matches the declared digest.
1. The file is synced to disk via `fsync()`.
1. The file is atomically moved to its permanent location via `rename(tmp_path, cas_path)`.
1. If the target blob already exists, the temporary file is unlinked immediately, achieving zero duplicate storage.

### DuckDB Relational Metadata Catalog

MuRegist persists catalog states in an embedded DuckDB database (`/var/lib/muregist/catalog/muregist.duckdb`). DuckDB eliminates SQLite database locking contention during multi-stage CI runs:

- **`crates`**: `id`, `name`, `created_at`, `owners`
- **`versions`**: `id`, `crate_id`, `version`, `cksum`, `created_at`, `yanked`
- **`dependencies`**: `version_id`, `name`, `req`, `features`, `optional`, `default_features`, `target`, `kind`
- **`canary_releases`**: `digest`, `crate_name`, `version`, `status`, `staged_at`, `expires_at`

______________________________________________________________________

## 5. Canary Release & Integration Promotion API

MuRegist features a staging gate for automated continuous delivery, enabling canary packages to be vetted against production test matrices before appearing in the public sparse index.

```
┌────────────────────────────────────────────────────────────────────────┐
│ 1. Stage Canary Package                                                │
│ POST /api/v1/canary/publish ──► Staged in CAS (Status: pending)        │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 2. Automated Integration Test Suite Runs                               │
│ GET /api/v1/canary/status ◄──► Response Header: canary-repository:...  │
└───────────────────┬────────────────────────────────┬───────────────────┘
                    │ Tests Pass                     │ Test Fails
                    ▼                                ▼
┌──────────────────────────────────────┐  ┌──────────────────────────────┐
│ 3a. Promote Candidate                │  │ 3b. Taint Candidate          │
│ POST /api/v1/canary/{digest}/promote │  │ POST /api/v1/canary/{digest}/│
│ Published to Sparse Index & Catalog  │  │ taint                        │
└──────────────────────────────────────┘  │ Blocked across all nodes     │
                                          └──────────────────────────────┘
```

### Endpoints

#### 1. Publish Canary Candidate

- **Method & Path**: `POST /api/v1/canary/publish`
- **Headers**:
  - `Authorization: Bearer <scoped_token>`
  - `Content-Type: application/octet-stream`
- **Response (`201 Created`)**:
  ```json
  {
    "crate": "k3-manager",
    "version": "0.4.1-rc.1",
    "digest": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
    "status": "pending",
    "expires_in_seconds": 3600
  }
  ```

#### 2. Query Canary Status

- **Method & Path**: `GET /api/v1/canary/status?digest=<digest>`
- **Response Headers**:
  - `canary-repository: verified` (or `pending`, `testing`, `tainted`)
- **Response Body**:
  ```json
  {
    "digest": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
    "status": "verified",
    "test_runs_passed": 4,
    "test_runs_failed": 0
  }
  ```

#### 3. Taint Broken Candidate

- **Method & Path**: `POST /api/v1/canary/{digest}/taint`
- **Effect**: Marks the digest as `tainted`. Further attempts to download or promote this candidate fail immediately with `410 Gone`.

#### 4. Promote Canary Candidate

- **Method & Path**: `POST /api/v1/canary/{digest}/promote`
- **Effect**: Atomically inserts the version record into DuckDB and appends the entry to the public Sparse Index path (`/index/...`).

______________________________________________________________________

## 6. Mutual TLS & Scoped Bearer Authentication

### Mutual TLS (mTLS) Ingress

All internal node-to-node communication runs over mTLS backed by the cluster `step-ca` authority:

- Workers authenticate with X.509 client certificates issued by `step-ca`.
- Reverse proxies terminate mTLS and forward verified Subject Common Name headers to MuRegist.

### Scoped Bearer Token Matrix

Bearer tokens are verified using salted Argon2id hashes:

| Token Scope    | Allowed Endpoints                      | Typical Consumer                            |
| :------------- | :------------------------------------- | :------------------------------------------ |
| `read`         | `GET /index/*`, `GET /api/v1/crates/*` | Developers, build nodes, CI compilation     |
| `publish`      | `PUT /api/v1/crates/new`               | Authorized CI release pipelines             |
| `canary-admin` | `/api/v1/canary/*`                     | Continuous delivery controllers (`MuConDe`) |
