# Native Backends

viewy has two backend families:

- `lite`, the compatibility backend backed by `webview/webview`;
- `native`, the per-platform backend family that talks directly to desktop
  APIs.

The public app API does not change between them. Backend selection is a
compile-time choice (`-d:viewyBackend=lite|native`), and native-only features
are exposed through capability gates rather than through platform-specific app
code.

This document describes the native backend architecture, the uniform Nim
backend contract, the custom asset-scheme model, and the interface section that
was frozen for Windows native work.

## Current Capability Matrix

Capabilities are advertised by `selectedBackendCaps` in
`src/viewy/backend/api.nim` and by each backend's runtime `caps` field. Code
that needs a capability should use the backend API helpers instead of branching
on operating system names.

| Backend selection | Platform | Capabilities |
| --- | --- | --- |
| `-d:viewyBackend=lite` | all supported platforms | none |
| `-d:viewyBackend=native` | Linux | `capScheme` |
| `-d:viewyBackend=native` | macOS | `capScheme`, `capMenu`, `capTray`, `capWindowEvents` |
| `-d:viewyBackend=native` | Windows | `capScheme`, `capMenu`, `capTray` |
| `-d:viewyBackend=native` | unsupported platforms | none; backend construction fails at compile time |

This matrix is intentionally capability-based. Windows menu/tray work, Linux
tray/menu work, and future lifecycle hooks should update the table only when
their backend slots and tests land.

## Uniform Backend API

Every backend implements the vtable-style `Backend` object in
`src/viewy/backend/api.nim`. The slots divide into four groups.

Lifecycle slots:

- `create(debug)` creates a native window/webview handle.
- `run(handle)` enters the platform event loop and blocks until termination.
- `terminate(handle)` requests shutdown from the UI thread.
- `destroy(handle)` releases backend-owned resources after the loop stops.

Webview slots:

- `setTitle`, `setSize`, `navigate`, and `setHtml` control the window and page
  load state.
- `eval` evaluates JavaScript in the active page.
- `init` registers JavaScript that runs before page scripts.
- `bindFn`, `unbind`, and `resolve` implement `window.<name>(...)` Promise
  bindings and complete pending calls.

Typed handoff slots:

- `dispatchEval` schedules backend-to-JavaScript event delivery.
- `dispatchResolve` completes a pending binding Promise from a worker or async
  continuation.
- `dispatchTerminate` requests shutdown from any thread.
- `dispatch` remains available for UI-thread-created work, but worker-created
  closures must not cross thread boundaries.

Capability-gated slots:

- `capScheme` requires `registerSchemeImpl`.
- `capMenu` requires `setAppMenuImpl`.
- `capTray` requires `trayCreateImpl`, `trayUpdateImpl`, and `trayDestroyImpl`.
- `capWindowEvents` requires `onWindowEventImpl`.

All synchronous slots are UI-thread operations. Worker-safe slots must copy
payloads into unmanaged storage before crossing threads, then reconstruct
Nim-managed values on the destination UI thread. The detailed ownership rules
are in [threading.md](threading.md).

## Runtime JavaScript And IPC

High-level app startup injects `viewyRuntimeJs`, which creates
`window.__viewy.call`, `window.__viewy.on`, `window.__viewy.off`, and
`window.__viewy.emit`.

Backends are responsible for making each exposed binding name available as a
Promise-returning `window.<name>` function. The native bridge contract is:

1. `window.<name>(...args)` creates a unique request id.
2. It sends an envelope containing `name`, `id`, and `args`, where `args` is a
   JSON string for the positional argument array.
3. The backend invokes the Nim `BindCallback(id, jsonArgs)` on the UI thread.
4. The app layer calls `resolve` or `dispatchResolve` with the same id and a
   JSON result string.
5. The injected bridge resolves or rejects the original JavaScript Promise.

Linux and macOS send envelopes through WebKit script message handlers. Windows
sends string messages through `chrome.webview.postMessage` and receives them via
WebView2 `WebMessageReceived`.

## Asset Scheme Model

Scheme asset mode generates an embedded multi-file `dist/` table and asks the
selected backend to serve it through `registerScheme`.

The backend-facing request/response model is backend-neutral:

- `AssetRequest.scheme` is the logical scheme name, currently `viewy`.
- `httpMethod`, `path`, `query`, `headers`, and `body` are Nim-owned copies.
- `AssetResponse` returns status, reason phrase, MIME type, headers, and body
  bytes.

The handler runs on the backend UI thread. If a platform receives native scheme
requests on another thread, it must first hop to the UI thread with unmanaged
storage and build the Nim request there.

Platform URL details differ:

- Linux registers the custom URI scheme with WebKitGTK.
- macOS registers `viewy://` with `WKURLSchemeHandler`.
- Windows maps `viewy://app/...` navigations onto
  `https://viewy.localhost/...` and serves them with WebView2
  `WebResourceRequested`, because WebView2 virtual-host style requests behave
  more like a secure browser origin than an arbitrary custom scheme.

The app and asset layers should treat those details as backend implementation
choices. The public capability is still `capScheme`.

## Platform Architecture

### Linux

The Linux native backend is a direct GTK/WebKitGTK implementation under
`src/viewy/backend/native/linux/`.

- `gtk_ffi.nim` declares the GTK functions needed for the window and event
  loop.
- `webkitgtk_ffi.nim` declares the WebKitGTK webview, user-script,
  JavaScript-evaluation, message-handler, and URI-scheme APIs.
- `backend.nim` owns the GTK window, WebKit webview, JavaScript bindings,
  typed handoff payloads, and `capScheme` registration.

Linux currently advertises `capScheme`. Tray and native menu work is tracked by
separate beads and should not be inferred from the existence of the native
window backend.

### macOS

The macOS native backend is split between Nim ownership code and small
Objective-C glue under `src/viewy/backend/native/darwin/`.

- `backend.nim` implements the backend contract, binding table, scheme/menu/tray
  callback routing, and typed handoffs.
- `glue.m` and `glue.h` wrap Cocoa and WebKit APIs that are more practical to
  express in Objective-C than in Nim imports.
- The backend uses `WKWebView`, `WKUserContentController`,
  `WKURLSchemeHandler`, `NSMenu`, and `NSStatusItem`.

macOS currently advertises `capScheme`, `capMenu`, `capTray`, and
`capWindowEvents`.

### Windows

The Windows native backend is a hand-written Win32/WebView2 implementation under
`src/viewy/backend/native/windows/`.

- `win32.nim` declares the required Win32, COM initialization, memory, and
  shell helpers.
- `com.nim` declares only the WebView2 COM interfaces the backend uses, pinned
  against the vendored SDK metadata.
- `webview2.nim` contains lifecycle helpers for environment/controller creation
  and baseline WebView2 settings.
- `webview2_loader.cc` is the small C++ translation unit used to load the
  WebView2 runtime entry point.
- `ipc_bridge.nim` contains pure JavaScript/envelope helpers for the WebView2
  binding bridge.
- `backend.nim` owns the Win32 window, message loop, WebView2 handles, binding
  callbacks, virtual-host scheme handling, and typed handoff payloads.

Windows currently advertises `capScheme`, `capMenu`, and `capTray`. IPC and
init-script parity are implemented with `AddScriptToExecuteOnDocumentCreated`
and `WebMessageReceived`. Scheme mode maps to `https://viewy.localhost/`
through WebView2 `WebResourceRequested`. Menu support uses HMENU menu bars with
ACCEL-table accelerators. Tray support uses `Shell_NotifyIconW` with Win32
popup menus and updates icons through the same tray update slot used for
light/dark icon swaps.

## Conformance And Gates

The test suite is organized in [tests/tiers.md](../tests/tiers.md).

- Tier 1 tests run headlessly and validate backend-neutral logic, RPC wrappers,
  runtime JavaScript, asset routing, and bridge helper contracts.
- Native compile smokes type-check platform FFI declarations and backend slot
  availability. They are gated by OS when the host cannot compile or run that
  platform's native code.
- Tier 2 tests create real windows and run against `-d:viewyBackend=lite` or
  `-d:viewyBackend=native` on hosts that can display the selected backend.

New backend capabilities should land with the narrowest useful tests first:
pure contract tests for serializable logic, compile smokes for platform FFI
shape, and windowed parity tests when the host environment can actually run the
backend.

## Interface Freeze

Freeze tag: `viewy-9lo`, recorded on June 14, 2026 after the macOS native
backend landed custom scheme handling, window lifecycle events, status item
tray support, global app menus, accelerator mapping, bundle Info.plist output,
and ad-hoc codesigning.

The frozen interface is the exported backend contract in
`src/viewy/backend/api.nim` plus this section. Windows native backend work must
implement against that contract. It must not freely edit interface shapes in
`api.nim` while adding Win32/WebView2 support: exported types, callback
signatures, capability names, vtable slot names, and slot signatures are frozen.
Platform capability-table updates are allowed when a backend implementation
lands and its tests prove the advertised slots exist. For example, the Windows
native backend may update `selectedBackendCaps` from `{}` to the capabilities
that its implementation actually provides.

Escape valve: if Windows discovers that a frozen vtable slot or type is
genuinely not implementable with the planned pure-Nim Win32/COM backend, file
an interface-change RFC bead. That bead re-opens the freeze gate, records the
specific incompatibility, includes the failed implementation evidence or spike
result, evaluates alternatives, and closes before any interface edit lands.
Valid RFC outcomes are:

- accept an interface change and update `api.nim` plus this section in the same
  change;
- reject the interface change and keep the Windows implementation behind the
  frozen contract;
- defer the platform feature by leaving the relevant Windows capability
  unadvertised.

Adjudication is by repository maintainer review on the RFC bead. The bead close
comment must state the chosen outcome and the evidence used.

The frozen backend contract has these parts:

- `BackendHandle` is an opaque backend-owned pointer.
- Required lifecycle slots: `create`, `destroy`, `run`, `terminate`.
- Required UI-thread webview slots: `setTitle`, `setSize`, `navigate`,
  `setHtml`, `eval`, `init`, `bindFn`, `unbind`, and `resolve`.
- Required worker-safe typed handoff slots: `dispatch`, `dispatchEval`,
  `dispatchResolve`, and `dispatchTerminate`.
- Capability-gated slots:
  - `capScheme` requires `registerSchemeImpl`.
  - `capMenu` requires `setAppMenuImpl`.
  - `capTray` requires `trayCreateImpl`, `trayUpdateImpl`, and
    `trayDestroyImpl`.
  - `capWindowEvents` requires `onWindowEventImpl`.
- Shared payload types: `AssetRequest`, `AssetResponse`, `Header`,
  `MenuItem`, `TrayOptions`, `WindowEvent`, and their callback types.

Threading and ownership are part of the interface, not implementation detail:
scheme, menu, tray, and window callbacks run on the backend UI thread with
Nim-owned copies of ids or payloads. Worker-thread or native-callback hops to
the backend UI thread must use unmanaged handoff storage as described in
[threading.md](threading.md); Nim-managed closures, strings, seqs, refs, or
objects must not cross those thread boundaries directly.

Selected backend capability gates are also part of the contract. Current gates:

- `-d:viewyBackend=lite` advertises no native capabilities.
- `-d:viewyBackend=native` on Linux advertises `capScheme`.
- `-d:viewyBackend=native` on macOS advertises `capScheme`, `capMenu`,
  `capTray`, and `capWindowEvents`.
- `-d:viewyBackend=native` on Windows advertises `capScheme`, `capMenu`, and
  `capTray`.
- `-d:viewyBackend=native` on unsupported platforms advertises no capabilities;
  importing `viewy/backend/select` and calling `newBackend()` fails at compile
  time until that platform backend lands.

## Cross-thread terminate contract

Decision: `dispatchTerminate` is a backend vtable slot.

The v1 webview backend exposed `dispatchTerminate` as a module-level helper in
`viewy/backend/wv/backend`. That worked while there was only one backend, but it
would force the native conformance tests to import backend-specific modules or
branch on the selected backend. v2 keeps termination backend-neutral by putting
the worker-safe terminate handoff next to the other typed cross-thread helpers:

- `dispatchEval` for backend-to-JavaScript event delivery;
- `dispatchResolve` for deferred RPC promise completion;
- `dispatchTerminate` for shutdown paths and windowed smoke tests.

The direct `terminate` slot remains a backend operation for UI-thread callers.
`dispatchTerminate` is the cross-thread API and must be safe to call from the UI
thread or a worker thread.

Native backend implementations must follow the same ownership model as
`dispatchEval` and `dispatchResolve`: no Nim-managed closure, string, seq, ref,
or object crosses the thread boundary. If a platform needs to hop from a worker
or native callback thread to the backend UI thread, it must copy the operation
into unmanaged storage first, schedule a top-level callback, and reconstruct any
Nim values on the UI thread before touching native handles. The detailed
handoff ownership rules live in [threading.md](threading.md).

Conformance tests should call `newBackend().dispatchTerminate(handle)` instead
of importing backend-specific terminate helpers. The old `wv` module export may
remain as a compatibility helper for existing tests during the transition, but
it is not the v2 backend contract.
