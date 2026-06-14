# Native backend design notes

This document records Phase 0 interface decisions for the v2 native-backend
work. Platform-specific implementation details will expand here as Linux,
macOS, and Windows backends land.

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

Selected backend capability gates are also frozen. As of this tag:

- `-d:viewyBackend=lite` advertises no native capabilities.
- `-d:viewyBackend=native` on Linux advertises `capScheme`.
- `-d:viewyBackend=native` on macOS advertises `capScheme`, `capMenu`,
  `capTray`, and `capWindowEvents`.
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
