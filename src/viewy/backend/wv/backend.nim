## webview/webview backend implementation.

import std/strformat

import ../api
import ./ffi

export api

type
  WvBackendError* = object of CatchableError
    ## Raised when the native webview backend returns an error status.

  Binding = ref object
    name: string
    cb: BindCallback

  DispatchSlot = ref object
    fn: DispatchProc

  DispatchPayload = object
    state: BackendHandle
    slot: int

  WvState = ref object
    webview: Webview
    mainThreadId: int
    bindings: seq[Binding]
    dispatches: seq[DispatchSlot]
    closed: bool

var liveStates {.global.}: seq[WvState]

proc toState(h: BackendHandle): WvState =
  doAssert h != nil, "viewy backend handle is nil"
  cast[WvState](h)

proc toHandle(state: WvState): BackendHandle =
  cast[BackendHandle](state)

proc expectOk(op: string; err: WebviewError) =
  if err != wvOk:
    raise newException(WvBackendError, &"{op} failed: {err}")

proc assertUiThread(state: WvState) =
  when not defined(release):
    doAssert getThreadId() == state.mainThreadId,
      "viewy backend operation must run on the UI thread"

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

proc bindTrampoline(id, req: ConstCString; arg: pointer) {.cdecl, gcsafe.} =
  let binding = cast[Binding](arg)
  binding.cb($cast[cstring](id), $cast[cstring](req))

proc dispatchTrampoline(w: Webview; arg: pointer) {.cdecl, gcsafe.} =
  discard w
  let payload = cast[ptr DispatchPayload](arg)
  let state = payload.state.toState
  let slotIndex = payload.slot
  deallocShared(payload)

  if slotIndex >= 0 and slotIndex < state.dispatches.len:
    let slot = state.dispatches[slotIndex]
    state.dispatches[slotIndex] = nil
    if slot != nil:
      slot.fn()

proc create(debug: bool): BackendHandle =
  let webview = webviewCreate(if debug: cint(1) else: cint(0), nil)
  if webview == nil:
    raise newException(WvBackendError, "webview_create failed")

  let state = WvState(
    webview: webview,
    mainThreadId: getThreadId(),
    bindings: @[],
    dispatches: @[],
    closed: false,
  )
  rootState state
  state.toHandle

proc destroy(h: BackendHandle) =
  let state = h.toState
  state.assertUiThread
  if not state.closed:
    state.closed = true
    expectOk("webview_destroy", webviewDestroy(state.webview))
    state.webview = nil
  unrootState state

proc run(h: BackendHandle) =
  let state = h.toState
  state.assertUiThread
  expectOk("webview_run", webviewRun(state.webview))

proc terminate(h: BackendHandle) =
  let state = h.toState
  state.assertUiThread
  expectOk("webview_terminate", webviewTerminate(state.webview))

proc dispatch(h: BackendHandle; fn: DispatchProc) {.gcsafe.} =
  let state = h.toState
  let slotIndex = state.dispatches.len
  state.dispatches.add DispatchSlot(fn: fn)

  let payload = cast[ptr DispatchPayload](allocShared0(sizeof(DispatchPayload)))
  if payload == nil:
    state.dispatches[slotIndex] = nil
    raise newException(WvBackendError, "webview_dispatch failed: out of memory")
  payload[] = DispatchPayload(state: h, slot: slotIndex)

  # TODO(viewy-na6): replace this GC-rooted closure slot placeholder with the
  # allocShared-backed typed handoff described in docs/threading.md. Passing a
  # worker-created closure through ORC is unsafe even though this proc is gcsafe.
  let err = webviewDispatch(state.webview, dispatchTrampoline, payload)
  if err != wvOk:
    state.dispatches[slotIndex] = nil
    deallocShared(payload)
    expectOk("webview_dispatch", err)

proc setTitle(h: BackendHandle; title: string) =
  let state = h.toState
  state.assertUiThread
  expectOk("webview_set_title", webviewSetTitle(state.webview, title.cstring))

proc setSize(h: BackendHandle; width, height: int; hints: WindowHints) =
  let state = h.toState
  state.assertUiThread
  expectOk("webview_set_size", webviewSetSize(state.webview, cint(width), cint(height),
    hints.toHint))

proc navigate(h: BackendHandle; url: string) =
  let state = h.toState
  state.assertUiThread
  expectOk("webview_navigate", webviewNavigate(state.webview, url.cstring))

proc setHtml(h: BackendHandle; html: string) =
  let state = h.toState
  state.assertUiThread
  expectOk("webview_set_html", webviewSetHtml(state.webview, html.cstring))

proc eval(h: BackendHandle; js: string) =
  let state = h.toState
  state.assertUiThread
  expectOk("webview_eval", webviewEval(state.webview, js.cstring))

proc init(h: BackendHandle; js: string) =
  let state = h.toState
  state.assertUiThread
  expectOk("webview_init", webviewInit(state.webview, js.cstring))

proc bindFn(h: BackendHandle; name: string; cb: BindCallback) =
  let state = h.toState
  state.assertUiThread
  if state.hasBinding(name):
    raise newException(WvBackendError, "webview_bind failed: duplicate binding " & name)

  let binding = Binding(name: name, cb: cb)
  expectOk("webview_bind", webviewBind(state.webview, name.cstring,
    bindTrampoline,
    cast[pointer](binding)))
  state.bindings.add binding

proc unbind(h: BackendHandle; name: string) =
  let state = h.toState
  state.assertUiThread
  expectOk("webview_unbind", webviewUnbind(state.webview, name.cstring))
  removeBinding(state, name)

proc resolve(h: BackendHandle; id: string; ok: bool; jsonResult: string) =
  let state = h.toState
  state.assertUiThread
  let status = if ok: cint(0) else: cint(1)
  expectOk("webview_return", webviewReturn(state.webview, id.cstring, status,
    jsonResult.cstring))

proc newBackend*(): Backend =
  ## Return the vtable implementation backed by vendored webview/webview.
  Backend(
    create: create,
    destroy: destroy,
    run: run,
    terminate: terminate,
    dispatch: dispatch,
    setTitle: setTitle,
    setSize: setSize,
    navigate: navigate,
    setHtml: setHtml,
    eval: eval,
    init: init,
    bindFn: bindFn,
    unbind: unbind,
    resolve: resolve,
  )
