# `action-runner-web` Architecture & Crate Reference

**Crate**: `action-runner-web`  
**Version**: `0.1.0` (Edition 2021)  
**Role**: Leptos CSR WebAssembly real-time CI queue monitor and job drill-down dashboard  
**Repository**: [`LMA1980/ActionRunner-web`](https://github.com/LMA1980/ActionRunner-web)  
**Rustdoc Reference**: [`action_runner_web` API Reference](../../api/action_runner_web/index.html)

---

## 1. Purpose & System Context

`action-runner-web` is a modern, single-page WebAssembly (WASM) frontend application built with the Leptos framework in Client-Side Rendering (CSR) mode.

It provides real-time observability into ActionRunner CI operations:
- Live display of queued, running, and completed jobs.
- Visual DAG stage dependency execution status.
- Real-time streaming log terminal over WebSockets with ANSI color parsing.
- Factory quality scorecard views (test pass rates, coverage metrics, benchmark charts).

---

## 2. Key Leptos Components & Views

### 2.1 `App`
Top-level router and layout container providing global dark mode theming and WebSocket connection management.

### 2.2 `QueueView`
Displays running and pending pipeline jobs:
- Shows worker node allocation and slot utilization.
- Highlights exclusive benchmark stages in progress (`exclusive: true`).

### 2.3 `JobDetailView` & `LogViewer`
- Virtualized scrolling terminal rendering thousands of log lines efficiently.
- Ansi color decoding and stage duration timing breakdown.

---

## 3. Web & Viewport Invariants (`AGENTS.md` §8)

1. **Dual-Layer Caching Protocol**:
   - HTML entry point (`index.html`) declares `Cache-Control: no-cache, no-store, must-revalidate`.
   - WASM, JS, and CSS static bundles utilize content-hash busting (`?v=<hash>`) with `no-cache, must-revalidate`.
2. **Mobile Viewport Optimization**:
   - Declares `<meta name="viewport" content="width=device-width, initial-scale=1.0">`.
   - Horizontal scrolling for wide data tables.
   - Form inputs enforce `font-size: 16px` to prevent automatic zoom on iOS Safari.

---

## 4. Inter-Crate Dependencies

- **Imports**: `leptos`, `wasm-bindgen`, `web-sys`, `js-sys`, `serde`, `serde_json`
- **Deployment**: Compiled to `wasm32-unknown-unknown` and served by `action-runner-controller` or static hosting.
