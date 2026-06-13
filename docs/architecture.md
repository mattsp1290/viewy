# Architecture

viewy is split into a small CLI, a Nim runtime library, a backend interface, and
one shipped backend built on the vendored `webview/webview` C API. The shape is
intentional: user code talks to stable library concepts, while backend details
stay behind a narrow vtable.

```text
+-----------------------------------------------------------------+
| CLI: viewy init | dev | build | doctor                          |
|  - scaffold templates, run Vite/Nim dev loop, generate assets   |
+-----------------------------------------------------------------+
| Library: viewy                                                  |
|  app.nim      high-level App lifecycle and backend wiring       |
|  rpc.nim      expose macro, jsony codecs, binding metadata      |
|  events.nim   backend-to-JavaScript event emission              |
|  assets.nim   embedded/scheme/served/dev asset mode selection   |
|  runtime_js   injected __viewy browser runtime                  |
+-----------------------------------------------------------------+
| Backend abstraction: backend/api.nim                            |
|  - opaque handles plus a vtable of operations                   |
|  - UI-thread-only calls and typed cross-thread dispatch helpers |
+-----------------------------------------------------------------+
| lite backend: backend/lite/*                                    |
|  backend.nim   vtable implementation and lifetime checks        |
|  handoff.nim   unmanaged cross-thread payload handoff           |
|  ffi.nim       hand-written webview C API bindings              |
|  build.nim     platform compiler and linker flags               |
+-----------------------------------------------------------------+
| vendor/webview: pinned webview/webview source and header        |
+-----------------------------------------------------------------+
```

## CLI Layer

The `viewy` CLI is a separate binary under `cli/`. It owns project workflow, not
runtime semantics:

- `viewy init` copies a vendored template into a new app.
- `viewy dev` runs the frontend dev server and compiles the Nim app with
  `-d:viewyDev=<url>`.
- `viewy build` runs the frontend build, generates Nim asset modules, and
  compiles the app.
- `viewy doctor` is currently reserved for Phase 3 diagnostics.

The CLI reads `viewy.json` through `viewy_cli/config.nim` and delegates runtime
behavior to the library. Generated assets follow the contracts documented in
`src/viewy/assets.nim` and `src/viewy/assets_served.nim`.

## Library Layer

`src/viewy.nim` re-exports the public library surface. Internally the runtime is
kept small and explicit:

- `app.nim` creates the backend handle, applies window settings, injects the
  browser runtime, binds every registered RPC proc, selects the content loading
  path, enters the blocking backend loop, and destroys the handle on exit.
- `rpc.nim` implements `expose`, JSON argument decoding and result encoding with
  jsony, async `Future[T]` completion, and binding metadata used by
  `-d:viewyDumpBindings`.
- `events.nim` serializes backend-to-JavaScript events into a call to
  `window.__viewy.emit(...)` and sends it through the backend's typed eval
  dispatch path.
- `assets.nim` chooses embedded, scheme, served, or dev-server loading.
- `assets_served.nim` implements the optional loopback authenticated asset
  server used by served mode.

The library does not require application code to know whether the active content
source is embedded HTML, a loopback server, or a Vite dev server. That decision
is made by compile-time defines and `newApp` options.

## Backend Abstraction

`backend/api.nim` defines `Backend` as an object containing function fields. It
is a vtable-style interface rather than a class hierarchy. That keeps the
runtime ARC/ORC-friendly, avoids inheritance for a tiny fixed surface, and lets
tests or future native backends pass their own implementations into `newApp`.

The backend surface is deliberately close to `webview/webview`: create, destroy,
run, terminate, dispatch, title/size, navigate, set HTML, eval, init, bind,
unbind, and resolve. viewy adds typed dispatch helpers:

- `dispatchEval` for worker-safe event delivery.
- `dispatchResolve` for worker-safe deferred RPC completion.
- `dispatchTerminate` for worker-safe shutdown paths and windowed smoke tests;
  see the [native backend design note](native-backends.md#cross-thread-terminate-contract).

Generic `dispatch(h, fn)` exists for UI-thread-created work, but the webview
backend rejects worker-created closure dispatch. Cross-thread app features use
typed payload handoff instead of moving GC-managed closures between threads.

## Lite Backend

The shipped lite backend lives in `src/viewy/backend/lite/` and wraps the
pinned `vendor/webview` source. The old import path
`viewy/backend/wv/backend` remains as a deprecated compatibility shim that
re-exports the lite backend for v1 applications.

`backend.nim` stores a shared native handle, records the UI thread id, checks
main-thread-only operations in debug builds, and maps the `Backend` vtable onto
webview calls. The native handle is treated as UI-thread owned. Destroying the
backend closes the handle before unrooting state so late worker handoffs fail
without touching a destroyed native webview.

`handoff.nim` is the cross-thread boundary for backend-to-JavaScript operations.
It copies strings into C-heap payloads, sends them through `webview_dispatch`
with a top-level C callback, copies bytes back into Nim strings on the UI
thread, performs the native operation, and frees every C allocation. See
[threading.md](threading.md) for the detailed ownership model.

## RPC And Events

RPC calls use the binding mechanism provided by `webview/webview`. JavaScript
calls an exposed function with positional JSON arguments; the generated Nim
wrapper decodes the arguments, invokes the exposed proc, and returns either a
jsony-encoded value or a structured error envelope through `webview_return`.

Async exposed procs return `Future[T]`. The immediate wrapper marks the reply as
pending, and app wiring completes the browser promise later through
`dispatchResolve`.

Events flow the other direction. Nim code calls `emit`, which jsony-serializes
the payload and queues JavaScript source through `dispatchEval`. The injected
runtime dispatches the event to registered browser callbacks. The precise
envelopes and metadata schema are documented in [protocol.md](protocol.md).

## Asset Modes

viewy has three content loading modes:

- Scheme mode is the default production asset mode in new `viewy.json` files.
  It builds a generated multi-file asset table. Until native backends implement
  custom scheme loading, the lite backend consumes that table through the same
  loopback served-mode fallback as served mode.
- Embedded mode is the legacy `assets = "single"` production path. The CLI
  builds a single-file frontend document and generates a Nim module whose
  `staticRead` content is loaded with `setHtml`.
- Served mode is the legacy `assets = "served"` production path for apps that need separate static
  assets or URL-addressed generated files. It embeds gzip-compressed assets,
  starts a `127.0.0.1:0` HTTP server with per-launch credentials, and navigates
  the webview to the generated document URL. See [served-mode.md](served-mode.md).
- Dev mode is selected with `-d:viewyDev=<url>`. The app navigates directly to
  the frontend dev server, normally Vite, so HMR stays in the frontend toolchain.

These modes are implementation details of app startup. RPC, events, threading
rules, and backend lifetime are the same in all modes.

## Threading Model

The supported runtime configuration is `--mm:orc --threads:on`. Backend
operations are main/UI-thread only except for generic `dispatch` and the typed
handoff helpers `dispatchEval`, `dispatchResolve`, and `dispatchTerminate`.
The lite backend records the thread that created the native handle and
asserts the UI-thread rule outside release builds.

Worker-thread `emit` and deferred RPC completion do not capture Nim closures or
strings across the thread boundary. Instead, they serialize on the caller's
thread, copy bytes into unmanaged C-heap payloads, and use typed webview
dispatch helpers. The UI-thread callback reconstructs local Nim strings before
calling `webview_eval`, `webview_return`, or `webview_terminate`.

The full ownership and shutdown behavior is documented in
[threading.md](threading.md).

## FFI And Vendoring

The `webview/webview` C API used by viewy is small, so the FFI is hand-written
in `backend/lite/ffi.nim` rather than generated by c2nim, futhark, or an external
binding package. This keeps dependencies low and limits the exposed native
surface to the functions viewy actually uses.

The backend compiles `vendor/webview/webview.cc` through `backend/lite/build.nim`.
That file is a local translation unit that includes the pinned upstream
`vendor/webview/webview.h` implementation/API. Platform flags live in
`build.nim`:

- Linux probes `gtk+-3.0` with `webkit2gtk-4.1`, falling back to
  `webkit2gtk-4.0`; `-d:viewyGtk4` selects `gtk4 webkitgtk-6.0`.
- macOS links WebKit and Cocoa and compiles the vendored source as Objective-C++.
- Windows supports MinGW and VCC, uses the built-in WebView2 loader, and links
  the required system libraries.

Pinning the vendored headers in `vendor/` makes CI and downstream builds
deterministic. The exact upstream versions and local patch notes are recorded in
the `PIN` files next to the vendored sources.

## Design Boundaries

The current architecture deliberately does not expose custom URL schemes,
native menus, trays, or multi-window primitives. Those are backend capabilities,
not library-layer concepts. The vtable exists so a future native backend can add
platform-specific implementation power while preserving the app, RPC, event,
and asset contracts used by existing viewy applications.
