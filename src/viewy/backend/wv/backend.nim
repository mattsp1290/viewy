## webview/webview backend implementation.

import std/[locks, strformat]

import ../api
import ./ffi
import ./handoff

export api

type
  WvBackendError* = object of CatchableError
    ## Raised when the native webview backend returns an error status.

  Binding = ref object
    name: string
    cb: BindCallback

  DispatchSlot = ref object
    fn: DispatchProc

  SharedState = object
    lock: Lock
    webview: Webview
    mainThreadId: int
    closed: bool

  WvState = ref object
    shared: ptr SharedState
    bindings: seq[Binding]
    dispatches: seq[DispatchSlot]

  DispatchPayload = object
    state: WvState
    slot: int

var liveStates {.global.}: seq[WvState]

proc toShared(h: BackendHandle): ptr SharedState =
  doAssert h != nil, "viewy backend handle is nil"
  cast[ptr SharedState](h)

proc toState(h: BackendHandle): WvState =
  let shared = h.toShared
  for state in liveStates:
    if state.shared == shared:
      return state
  raise newException(WvBackendError, "viewy backend handle is not live")

proc toHandle(state: WvState): BackendHandle =
  cast[BackendHandle](state.shared)

proc expectOk(op: string; err: WebviewError) =
  if err != wvOk:
    raise newException(WvBackendError, &"{op} failed: {err}")

proc assertUiThread(state: WvState) =
  when not defined(release):
    doAssert getThreadId() == state.shared.mainThreadId,
      "viewy backend operation must run on the UI thread"

proc requireOpen(shared: ptr SharedState; op: string) =
  if shared.closed or shared.webview == nil:
    raise newException(WvBackendError, op & " failed: backend is closed")

proc requireOpen(state: WvState; op: string) =
  state.shared.requireOpen(op)

proc openWebview(shared: ptr SharedState; op: string): Webview =
  acquire(shared.lock)
  result = shared.webview
  let isClosed = shared.closed or result == nil
  release(shared.lock)
  if isClosed:
    raise newException(WvBackendError, op & " failed: backend is closed")

proc closeWebview(shared: ptr SharedState): Webview =
  acquire(shared.lock)
  if not shared.closed:
    shared.closed = true
    result = shared.webview
    shared.webview = nil
  release(shared.lock)

proc toHint(hint: WindowHints): WebviewHint =
  case hint
  of whNone: wvHintNone
  of whMin: wvHintMin
  of whMax: wvHintMax
  of whFixed: wvHintFixed

proc rootState(state: WvState) =
  liveStates.add state

proc unrootState(state: WvState) =
  for i in 0 ..< liveStates.len:
    if liveStates[i] == state:
      liveStates.delete i
      return

proc removeBinding(state: WvState; name: string) =
  for i in 0 ..< state.bindings.len:
    if state.bindings[i].name == name:
      state.bindings.delete i
      return

proc hasBinding(state: WvState; name: string): bool =
  for binding in state.bindings:
    if binding.name == name:
      return true

proc toString(s: ConstCString): string =
  let c = cast[cstring](s)
  if c == nil:
    ""
  else:
    $c

proc bindTrampoline(id, req: ConstCString; arg: pointer) {.cdecl, gcsafe.} =
  let binding = cast[Binding](arg)
  try:
    binding.cb(id.toString(), req.toString())
  except CatchableError:
    discard

proc dispatchTrampoline(w: Webview; arg: pointer) {.cdecl, gcsafe.} =
  discard w
  let payload = cast[ptr DispatchPayload](arg)
  let state = payload.state
  let slotIndex = payload.slot
  deallocShared(payload)

  if slotIndex >= 0 and slotIndex < state.dispatches.len:
    let slot = state.dispatches[slotIndex]
    state.dispatches[slotIndex] = nil
    if slot != nil:
      try:
        slot.fn()
      except CatchableError:
        discard

proc create(debug: bool): BackendHandle =
  let webview = webviewCreate(if debug: cint(1) else: cint(0), nil)
  if webview == nil:
    raise newException(WvBackendError, "webview_create failed")

  let shared = cast[ptr SharedState](allocShared0(sizeof(SharedState)))
  if shared == nil:
    discard webviewDestroy(webview)
    raise newException(WvBackendError, "webview_create failed: out of memory")
  shared[] = SharedState(
    webview: webview,
    mainThreadId: getThreadId(),
    closed: false,
  )
  initLock(shared.lock)

  let state = WvState(
    shared: shared,
    bindings: @[],
    dispatches: @[],
  )
  rootState state
  state.toHandle

proc destroy(h: BackendHandle) =
  let state = h.toState
  state.assertUiThread
  let webview = closeWebview(state.shared)
  if webview != nil:
    expectOk("webview_destroy", webviewDestroy(webview))
  unrootState state
  # SharedState intentionally remains allocated after destroy. BackendHandle is
  # an unmanaged pointer that worker threads may still hold; keeping the closed
  # state readable lets late typed handoffs fail before touching native handles.

proc run(h: BackendHandle) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("webview_run")
  expectOk("webview_run", webviewRun(state.shared.webview))

proc terminate(h: BackendHandle) {.gcsafe.} =
  let shared = h.toShared
  when not defined(release):
    doAssert getThreadId() == shared.mainThreadId,
      "viewy backend operation must run on the UI thread"
  expectOk("webview_terminate", webviewTerminate(shared.openWebview(
      "webview_terminate")))

proc dispatch(h: BackendHandle; fn: DispatchProc) {.gcsafe.} =
  let state = block:
    {.cast(gcsafe).}:
      h.toState
  if getThreadId() != state.shared.mainThreadId:
    raise newException(WvBackendError,
      "webview_dispatch failed: closure dispatch is UI-thread only; use typed handoff")
  state.requireOpen("webview_dispatch")
  let slotIndex = state.dispatches.len
  state.dispatches.add DispatchSlot(fn: fn)

  let payload = cast[ptr DispatchPayload](allocShared0(sizeof(DispatchPayload)))
  if payload == nil:
    state.dispatches[slotIndex] = nil
    raise newException(WvBackendError, "webview_dispatch failed: out of memory")
  payload[] = DispatchPayload(state: state, slot: slotIndex)

  # Generic closure dispatch is intentionally limited to UI-thread-created work.
  # Cross-thread app operations use the typed unmanaged helpers below.
  let err = webviewDispatch(state.shared.webview, dispatchTrampoline, payload)
  if err != wvOk:
    state.dispatches[slotIndex] = nil
    deallocShared(payload)
    expectOk("webview_dispatch", err)

proc setTitle(h: BackendHandle; title: string) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("webview_set_title")
  expectOk("webview_set_title", webviewSetTitle(state.shared.webview,
      title.cstring))

proc setSize(h: BackendHandle; width, height: int; hints: WindowHints) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("webview_set_size")
  expectOk("webview_set_size", webviewSetSize(state.shared.webview, cint(width),
      cint(height),
    hints.toHint))

proc navigate(h: BackendHandle; url: string) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("webview_navigate")
  expectOk("webview_navigate", webviewNavigate(state.shared.webview, url.cstring))

proc setHtml(h: BackendHandle; html: string) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("webview_set_html")
  expectOk("webview_set_html", webviewSetHtml(state.shared.webview, html.cstring))

proc eval(h: BackendHandle; js: string) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("webview_eval")
  expectOk("webview_eval", webviewEval(state.shared.webview, js.cstring))

proc init(h: BackendHandle; js: string) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("webview_init")
  expectOk("webview_init", webviewInit(state.shared.webview, js.cstring))

proc bindFn(h: BackendHandle; name: string; cb: BindCallback) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("webview_bind")
  if state.hasBinding(name):
    raise newException(WvBackendError, "webview_bind failed: duplicate binding " & name)

  let binding = Binding(name: name, cb: cb)
  expectOk("webview_bind", webviewBind(state.shared.webview, name.cstring,
    bindTrampoline,
    cast[pointer](binding)))
  state.bindings.add binding

proc unbind(h: BackendHandle; name: string) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("webview_unbind")
  expectOk("webview_unbind", webviewUnbind(state.shared.webview, name.cstring))
  removeBinding(state, name)

proc resolve(h: BackendHandle; id: string; ok: bool; jsonResult: string) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("webview_return")
  let status = if ok: cint(0) else: cint(1)
  expectOk("webview_return", webviewReturn(state.shared.webview, id.cstring, status,
    jsonResult.cstring))

proc dispatchEval*(h: BackendHandle; js: string) {.gcsafe.} =
  ## Thread-safe eval handoff for serialized backend-to-JS payloads.
  let shared = h.toShared
  acquire(shared.lock)
  try:
    shared.requireOpen("webview_dispatch")
    handoff.dispatchEval(shared.webview, js)
  finally:
    release(shared.lock)

proc dispatchResolve*(h: BackendHandle; id: string; ok: bool;
    jsonResult: string) {.gcsafe.} =
  ## Thread-safe resolve handoff for deferred RPC completions.
  let shared = h.toShared
  acquire(shared.lock)
  try:
    shared.requireOpen("webview_dispatch")
    handoff.dispatchResolve(shared.webview, id, ok, jsonResult)
  finally:
    release(shared.lock)

proc dispatchTerminate*(h: BackendHandle) {.gcsafe.} =
  ## Thread-safe terminate handoff used by stress tests and shutdown paths.
  let shared = h.toShared
  acquire(shared.lock)
  try:
    shared.requireOpen("webview_dispatch")
    handoff.dispatchTerminate(shared.webview)
  finally:
    release(shared.lock)

proc newBackend*(): Backend =
  ## Return the vtable implementation backed by vendored webview/webview.
  Backend(
    create: create,
    destroy: destroy,
    run: run,
    terminate: terminate,
    dispatch: dispatch,
    dispatchEval: dispatchEval,
    dispatchResolve: dispatchResolve,
    setTitle: setTitle,
    setSize: setSize,
    navigate: navigate,
    setHtml: setHtml,
    eval: eval,
    init: init,
    bindFn: bindFn,
    unbind: unbind,
    resolve: resolve,
    caps: {},
  )
