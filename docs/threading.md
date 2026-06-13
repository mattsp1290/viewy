# Threading model

viewy supports `--mm:orc --threads:on`. Under ORC, reference counting is not
atomic, so a GC-managed closure or string created on a worker thread must not be
transferred to the UI thread by capture. `{.gcsafe.}` only says the callback may
run while the GC is active; it does not make captured state safe to move between
threads.

This document refines the spec section 4.6 rule:

- all backend operations except `dispatch` are main/UI-thread only;
- worker-thread `emit` and deferred `resolve` must route through `dispatch`;
- the handoff must not transfer Nim-managed closures across the thread boundary.

## Binding invariant

No Nim-managed value may cross a thread boundary by pointer, capture, userdata,
or `GC_ref`. This includes `proc() {.closure.}`, `string`, `seq`, `ref`, object
graphs containing managed fields, and backend-owned `App` or handle state.

Every cross-thread backend path must instead copy the required data into
unmanaged storage before scheduling a top-level callback. The callback may
construct fresh Nim-managed values only after it is running on the destination
thread that will own and release those values.

This invariant is stronger than "the callback is `{.gcsafe.}`" and stronger
than "the object was `GC_ref`'d". Under ORC, moving managed objects between
worker and UI threads is a memory safety bug class, not an annotation issue.

## Decision

Use a small backend-local handoff layer built on C-heap owned payloads:

1. The caller serializes the operation into plain bytes on its current thread.
2. The handoff layer allocates the `HandoffPayload` object and each byte buffer
   with `malloc`, including a trailing NUL byte, and zero-initializes the
   allocation.
3. The payload is passed to `webview_dispatch` with a top-level static callback.
4. The UI-thread callback copies bytes into UI-thread Nim strings, performs the
   backend operation, and releases the unmanaged payload with `free`.

No new package dependency is required. The mechanism uses the platform C runtime
allocator plus the already-vendored `webview_dispatch` API. The C heap is used
instead of Nim's shared allocator because Windows stress testing exposed
allocator crashes when many accepted webview dispatch callbacks freed shared
payloads.

Channels or `isolate` are deliberately not the first implementation. They can be
added later if the public API needs a general-purpose cross-thread queue, but
the Phase 1 requirements primarily need two typed message paths: event emission
and RPC promise resolution. The backend also provides a small terminate handoff
for stress tests and shutdown paths.

## Callback domains

There are two callback domains, and they use different ownership rules:

- Worker-to-UI features such as `emit`, deferred RPC `resolve`, and worker-safe
  termination are cross-thread paths. They must use typed unmanaged payloads
  (`dispatchEval`, `dispatchResolve`, `dispatchTerminate`) and top-level
  `{.cdecl, gcsafe.}` callbacks. Only bytes and plain fields cross.
- UI-thread backend callbacks such as custom scheme handlers, menu/tray item
  dispatch, and window lifecycle events may invoke Nim closures with
  Nim-managed request/response values only when the native event has already
  been copied onto the backend UI thread. If a platform receives one of those
  native events on another thread, that platform backend must first perform an
  unmanaged handoff to the UI thread, then build the Nim `AssetRequest`,
  `MenuItem` id, or `WindowEvent` there.

Backend implementations must not mix these models. Scheme/menu/window callback
APIs are ergonomic Nim closures at the UI-thread boundary; they are not a
permission to move those closures or their captured state across native worker
threads.

## Payload shape

The unmanaged payload should be a tiny tagged object. Allocate
`HandoffPayload` itself with the C heap helper; `webview_dispatch` receives only
that unmanaged pointer.

```nim
type
  HandoffKind = enum
    hkEval
    hkResolve
    hkTerminate

  SharedBytes = object
    len: int
    data: ptr UncheckedArray[char]

  HandoffPayload = object
    kind: HandoffKind
    ok: bool
    a: SharedBytes
    b: SharedBytes
```

`SharedBytes` owns a NUL-terminated byte copy allocated with the C heap helper.
`a` and `b` are interpreted by `kind`:

- `hkEval`: `a` is the complete JavaScript source to pass to `webview_eval`;
  `b` is empty.
- `hkResolve`: `a` is the webview bind request id; `b` is the JSON result; `ok`
  maps to `webview_return` status `0` or `1`.
- `hkTerminate`: no semantic byte fields are required; the current helper still
  carries empty C-heap byte buffers that are freed by the same ownership path.

The C callback passed to `webview_dispatch` must be a top-level proc with the C
signature from `ffi.nim`, not a closure:

```nim
proc runHandoff(w: Webview; arg: pointer) {.cdecl, gcsafe.}
```

It casts `arg` to `ptr HandoffPayload`, copies the byte fields into local Nim
strings on the UI thread, runs the requested operation, then frees every
C-heap allocation exactly once.

## Emit path

`emit(event, payload)` remains callable from worker threads.

The caller serializes `payload` with jsony on the calling thread, encodes
`event` as a JSON string literal, and constructs the final JavaScript source
for:

```js
window.__viewy.emit("eventName", payloadJson)
```

The final JS source is copied into `SharedBytes` and dispatched as `hkEval`.
The UI thread callback calls `webview_eval(w, js)`.

This keeps jsony serialization and JavaScript escaping on the originating
thread, but transfers only unmanaged bytes. The worker-created Nim strings die
on the worker thread after the copy; the UI thread receives fresh Nim strings
created from the unmanaged bytes.

## Resolve path

Synchronous bound callbacks already run on the UI thread and can call
`webview_return` directly through the backend `resolve` operation.

Deferred or async results may complete on a worker or async continuation thread.
Those paths must not capture `id` or `jsonResult` in a worker-created closure.
Instead:

1. serialize the success value or structured error envelope to JSON;
2. copy the request id and JSON result into `SharedBytes`;
3. dispatch an `hkResolve` payload;
4. on the UI thread, call `webview_return(w, id, status, result)`.

The status mapping is fixed by the backend API: `ok = true` maps to status `0`,
and `ok = false` maps to status `1`.

## Async RPC integration

`expose` supports procs returning `std/asyncdispatch.Future[T]`. The generated
wrapper starts the future, returns an immediate `RpcReply` with `pending = true`,
and completes the webview promise later through the resolver supplied by app
wiring.

The resolver is the integration boundary. For the webview backend it must route
through `dispatchResolve`, not direct `resolve`, because an `asyncdispatch`
continuation may run outside the UI-thread-only backend call path. The resolver
copies the bind request id and JSON result into the unmanaged handoff described
above, then `webview_return` runs on the UI thread.

The application event loop must also pump `std/asyncdispatch` while the native
webview loop is running. Until the high-level `run()` API owns that loop
integration, tests can drive async RPC wrappers by calling `poll()`; production
app wiring should arrange an equivalent pump around the blocking backend
`run()`.

## Ownership rules

- The caller owns all Nim-managed strings and values before calling the handoff
  helper.
- The handoff helper copies all bytes into C-heap storage before calling
  `webview_dispatch`. The payload must contain only plain fields and pointers to
  unmanaged byte buffers.
- If allocation fails, the helper raises or returns an error before dispatching.
- If `webview_dispatch` returns a non-success status synchronously, according to
  the FFI wrapper's webview error convention, the helper frees the payload
  before returning.
- If `webview_dispatch` accepts the payload, the UI-thread callback owns it and
  must free it after running or dropping the operation.
- The UI-thread callback must copy payload bytes into local Nim strings before
  freeing the unmanaged payload.
- No `proc() {.closure.}`, `string`, `seq`, `ref`, or other ORC-managed object
  may be stored in `HandoffPayload`.
- `GC_ref` is not an accepted cross-thread ownership transfer mechanism for
  viewy backend callbacks. Backend userdata that crosses threads must be
  unmanaged or plain data whose lifetime is explicit outside ORC.

The generic backend `dispatch(h, fn: DispatchProc)` is still useful for
main-thread-created work, but app-level cross-thread features must use the typed
handoff helpers rather than passing a worker-created closure.

## Lifecycle and failure modes

The webview backend should store the UI thread id at `create` and keep the debug
assertions required by spec section 4.6: every backend operation except
`dispatch` must assert it is running on that UI thread.

The backend should track accepting-handoffs separately from native-handle
lifetime. Once termination starts, new `emit` and deferred `resolve` payloads
are best-effort:

- if the backend is no longer accepting handoffs, drop the payload before calling
  `webview_dispatch`;
- if `webview_dispatch` returns an error, free and drop the payload;
- if a payload reaches the UI thread after shutdown has started, free it and
  skip the native operation unless it is the termination handoff.

Delivery after termination is not guaranteed. The guarantee is memory safety:
payload ownership is explicit, and every accepted callback path has a single
owner responsible for freeing unmanaged storage.

`destroy` remains main-thread only and must run after `run` exits. It must stop
accepting new handoffs before releasing the native handle so later dispatch
attempts fail before touching a destroyed webview handle. Already accepted
UI-thread callbacks still guard native operations against a destroyed handle.

## Implementation notes

- Keep `runHandoff` top-level and `{.cdecl, gcsafe.}`.
- Prefer one helper for copying a Nim string to `SharedBytes` and one helper for
  freeing a partially-built payload, so allocation failures do not leak.
- Keep generic closure dispatch limited to UI-thread-created work; cross-thread
  app operations must use typed handoff helpers.
- Validation belongs in the CI valgrind bead: `test_emit_stress` plus a
  scheme-flood test should pass under `--mm:orc -d:useMalloc` and valgrind on
  Linux with zero definitely-lost leaks and zero invalid reads. Until that job
  exists, local stress tests are useful smoke coverage but are not the memory
  safety acceptance bar.
