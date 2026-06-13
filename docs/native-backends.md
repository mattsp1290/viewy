# Native backend design notes

This document records Phase 0 interface decisions for the v2 native-backend
work. Platform-specific implementation details will expand here as Linux,
macOS, and Windows backends land.

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
