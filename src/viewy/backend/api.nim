## Backend abstraction (spec section 4.1): the minimal vtable-style
## interface every backend must satisfy.

type
  BackendHandle* = pointer
    ## Opaque backend-owned native webview handle.

  WindowHints* = enum
    ## Window sizing hint passed through to the backend implementation.
    whNone = 0
    whMin = 1
    whMax = 2
    whFixed = 3

  DispatchProc* = proc() {.closure, gcsafe.}
    ## Work item scheduled onto the backend UI thread. Captured state must be
    ## safe to hand off under ORC when dispatching across threads.

  BindCallback* = proc(id, jsonArgs: string) {.closure, gcsafe.}
    ## UI-thread callback invoked by the backend with a request id and raw JSON
    ## args.

  Capability* = enum
    ## Optional backend features. High-level APIs use this set to decide
    ## whether native-only behavior is available on the selected backend.
    capScheme
    capMenu
    capTray
    capWindowEvents

  Header* = tuple[name, value: string]
    ## HTTP-style header pair used by asset scheme requests and responses.

  AssetRequest* = object
    ## Request passed to a backend scheme handler.
    scheme*: string
    httpMethod*: string
    path*: string
    query*: string
    headers*: seq[Header]
    body*: string

  AssetResponse* = object
    ## Complete in-memory response returned by an asset scheme handler.
    status*: int
    statusText*: string
    mimeType*: string
    headers*: seq[Header]
    body*: string

  AssetHandler* = proc(request: AssetRequest): AssetResponse {.closure, gcsafe.}
    ## Handler used by native scheme backends and the shared asset pipeline.
    ## Backends invoke it on the backend UI thread only, with request
    ## bytes/headers already copied into Nim-owned values on that thread. Nim
    ## managed request/response objects must not be moved across worker or
    ## native callback threads.

  MenuItemKind* = enum
    ## Native menu item shape.
    miCommand
    miSeparator
    miSubmenu
    miCheckbox
    miRadio

  MenuItem* = object
    ## Backend-neutral native menu description. Dispatch is by stable `id`.
    id*: string
    label*: string
    accelerator*: string
    kind*: MenuItemKind
    enabled*: bool
    checked*: bool
    children*: seq[MenuItem]

  MenuCallback* = proc(id: string) {.closure, gcsafe.}
    ## Callback invoked on the backend UI thread when a backend dispatches a
    ## menu or tray menu item id. The id must be a Nim-owned copy of the native
    ## event payload.

  TrayOptions* = object
    ## Backend-neutral system tray configuration.
    id*: string
    tooltip*: string
    iconPath*: string
    templateIconPath*: string
    menu*: seq[MenuItem]

  WindowEventKind* = enum
    ## Native window lifecycle events surfaced by backends.
    weClose
    weFocus
    weBlur
    weResize

  WindowEvent* = object
    ## Backend-originated native window event. Resize events set width/height.
    kind*: WindowEventKind
    width*: int
    height*: int

  WindowEventCallback* = proc(event: WindowEvent) {.closure, gcsafe.}
    ## Callback invoked by a backend on the backend UI thread for native window
    ## lifecycle events. Backends that receive lifecycle notifications on
    ## another thread must use an unmanaged handoff before invoking it.

  Backend* = object
    create*: proc(debug: bool): BackendHandle {.closure.}
      ## Main thread only. Create and return a backend handle; `debug`
      ## enables backend-specific developer tooling when available.

    destroy*: proc(h: BackendHandle) {.closure.}
      ## Main thread only. Destroy a handle after `run` has returned or the
      ## backend has otherwise been terminated.

    run*: proc(h: BackendHandle) {.closure.}
      ## Main thread only. Enter the backend event loop; this call blocks
      ## until the window terminates.

    terminate*: proc(h: BackendHandle) {.closure, gcsafe.}
      ## Main thread only. Request that the backend event loop stop.

    dispatch*: proc(h: BackendHandle, fn: DispatchProc) {.closure, gcsafe.}
      ## Schedule `fn` to run on the backend UI thread. Implementations must
      ## not move worker-created GC-managed closures across threads under ORC;
      ## backend-specific typed handoff helpers carry cross-thread payloads.

    dispatchEval*: proc(h: BackendHandle, js: string) {.closure, gcsafe.}
      ## Schedule JavaScript evaluation from the UI thread or a worker thread.
      ## Implementations must copy `js` into unmanaged storage before crossing
      ## threads; this is the backend-to-JS event handoff path.

    dispatchResolve*: proc(h: BackendHandle; id: string; ok: bool;
        jsonResult: string) {.closure, gcsafe.}
      ## Schedule completion of a JavaScript binding Promise from the UI thread
      ## or a worker thread. Implementations must copy string payloads into
      ## unmanaged storage before crossing threads.

    dispatchTerminate*: proc(h: BackendHandle) {.closure, gcsafe.}
      ## Request backend termination from the UI thread or a worker thread.
      ## Implementations must use the same unmanaged handoff discipline as
      ## `dispatchEval` and `dispatchResolve` before touching native handles.

    setTitle*: proc(h: BackendHandle, title: string) {.closure.}
      ## Main thread only. Set the native window title.

    setSize*: proc(h: BackendHandle, width, height: int,
        hints: WindowHints) {.closure.}
      ## Main thread only. Set the native window size and sizing hint.

    navigate*: proc(h: BackendHandle, url: string) {.closure.}
      ## Main thread only. Navigate the webview to a URL, used for dev-server
      ## and served-asset modes.

    setHtml*: proc(h: BackendHandle, html: string) {.closure.}
      ## Main thread only. Load an HTML string directly into the webview.

    eval*: proc(h: BackendHandle, js: string) {.closure.}
      ## Main thread only. Evaluate JavaScript in the active page context.

    init*: proc(h: BackendHandle, js: string) {.closure.}
      ## Main thread only. Register JavaScript that the backend injects before
      ## page scripts run.

    bindFn*: proc(h: BackendHandle, name: string, cb: BindCallback) {.closure.}
      ## Main thread only. Bind a JavaScript-exposed function name to a Nim
      ## callback that receives the webview request id and raw JSON args.

    unbind*: proc(h: BackendHandle, name: string) {.closure.}
      ## Main thread only. Remove a previously bound JavaScript function.

    resolve*: proc(h: BackendHandle, id: string, ok: bool,
        jsonResult: string) {.closure.}
      ## Main thread only. Complete a pending bound-call promise. Backends map
      ## `ok = true` to a success status and `ok = false` to a rejection
      ## status; for `webview_return`, that is status 0 or a non-zero status
      ## such as 1 respectively.

    caps*: set[Capability]
      ## Optional features implemented by this backend. Any advertised
      ## capability requires its matching vtable slot or slots to be non-nil.

    registerSchemeImpl*: proc(h: BackendHandle; scheme: string;
        handler: AssetHandler) {.closure.}
      ## Main thread only. Register a custom asset scheme handler for a handle.
      ## The backend invokes `handler` later on the backend UI thread only, with
      ## request payloads copied into Nim-owned values before invocation.

    setAppMenuImpl*: proc(h: BackendHandle; menu: seq[MenuItem];
        cb: MenuCallback) {.closure.}
      ## Main thread only. Install or replace the app/window menu.
      ## The backend invokes `cb` later on the backend UI thread only, with the
      ## dispatched item id copied into a Nim-owned string before invocation.

    trayCreateImpl*: proc(h: BackendHandle; options: TrayOptions;
        cb: MenuCallback) {.closure.}
      ## Main thread only. Create a native tray item for this backend handle.
      ## The backend invokes `cb` later on the backend UI thread only, with the
      ## dispatched item id copied into a Nim-owned string before invocation.

    trayUpdateImpl*: proc(h: BackendHandle; id: string;
        options: TrayOptions) {.closure.}
      ## Main thread only. Update an existing native tray item.

    trayDestroyImpl*: proc(h: BackendHandle; id: string) {.closure.}
      ## Main thread only. Destroy an existing native tray item.

    onWindowEventImpl*: proc(h: BackendHandle;
        cb: WindowEventCallback) {.closure.}
      ## Main thread only. Subscribe to native window lifecycle events.
      ## The backend invokes `cb` later on the backend UI thread only. Native
      ## events received on other threads must hop through an unmanaged handoff
      ## before callback invocation.

const selectedBackend* {.strdefine: "viewyBackend".} = "native"
  ## Compile-time backend selection used by public APIs to reject capabilities
  ## the selected backend cannot provide.

when selectedBackend == "native":
  when defined(macosx):
    const selectedBackendCaps*: set[Capability] = {capScheme, capMenu, capTray,
        capWindowEvents}
  else:
    const selectedBackendCaps*: set[Capability] = {capScheme}
elif selectedBackend == "lite":
  const selectedBackendCaps*: set[Capability] = {}
else:
  {.error: "unsupported -d:viewyBackend value; expected 'native' or 'lite'".}

template requireSelectedBackendCap*(cap: static[Capability];
    operation: static[string]) =
  when cap notin selectedBackendCaps:
    {.error: operation & " requires a backend capability that -d:viewyBackend=" &
        selectedBackend & " does not provide".}

proc requireBackendCap*(backend: Backend; cap: Capability; operation: string) =
  doAssert cap in backend.caps,
      operation & " requires a backend capability that this backend does not provide"
  case cap
  of capScheme:
    doAssert backend.registerSchemeImpl != nil,
        "capScheme requires a registerScheme vtable slot"
  of capMenu:
    doAssert backend.setAppMenuImpl != nil,
        "capMenu requires a setAppMenu vtable slot"
  of capTray:
    doAssert backend.trayCreateImpl != nil and backend.trayUpdateImpl != nil and
        backend.trayDestroyImpl != nil,
        "capTray requires trayCreate, trayUpdate, and trayDestroy vtable slots"
  of capWindowEvents:
    doAssert backend.onWindowEventImpl != nil,
        "capWindowEvents requires an onWindowEvent vtable slot"

template registerScheme*(backend: Backend; h: BackendHandle; scheme: string;
    handler: AssetHandler) =
  requireSelectedBackendCap(capScheme, "registerScheme")
  let b = backend
  requireBackendCap(b, capScheme, "registerScheme")
  b.registerSchemeImpl(h, scheme, handler)

template setAppMenu*(backend: Backend; h: BackendHandle; menu: seq[MenuItem];
    cb: MenuCallback) =
  requireSelectedBackendCap(capMenu, "setAppMenu")
  let b = backend
  requireBackendCap(b, capMenu, "setAppMenu")
  b.setAppMenuImpl(h, menu, cb)

template trayCreate*(backend: Backend; h: BackendHandle; options: TrayOptions;
    cb: MenuCallback) =
  requireSelectedBackendCap(capTray, "trayCreate")
  let b = backend
  requireBackendCap(b, capTray, "trayCreate")
  b.trayCreateImpl(h, options, cb)

template trayUpdate*(backend: Backend; h: BackendHandle; id: string;
    options: TrayOptions) =
  requireSelectedBackendCap(capTray, "trayUpdate")
  let b = backend
  requireBackendCap(b, capTray, "trayUpdate")
  b.trayUpdateImpl(h, id, options)

template trayDestroy*(backend: Backend; h: BackendHandle; id: string) =
  requireSelectedBackendCap(capTray, "trayDestroy")
  let b = backend
  requireBackendCap(b, capTray, "trayDestroy")
  b.trayDestroyImpl(h, id)

template onWindowEvent*(backend: Backend; h: BackendHandle;
    cb: WindowEventCallback) =
  requireSelectedBackendCap(capWindowEvents, "onWindowEvent")
  let b = backend
  requireBackendCap(b, capWindowEvents, "onWindowEvent")
  b.onWindowEventImpl(h, cb)
