## Native Linux backend backed by GTK3 and WebKitGTK 4.1.
##
## This module owns the core window/webview lifecycle. Higher-level native
## features such as RPC binding, custom schemes, menus, and tray integration are
## implemented by later backend slices.

import std/locks

import ../../api
import ./webkitgtk_ffi

export api

type
  LinuxBackendError* = object of CatchableError
    ## Raised when the native Linux backend cannot complete an operation.

  SharedState = object
    lock: Lock
    mainThreadId: int
    closed: bool
    window: ptr GtkWidget
    box: ptr GtkWidget
    manager: ptr WebKitUserContentManager
    webviewWidget: ptr GtkWidget
    webview: ptr WebKitWebView

  LinuxState = ref object
    shared: ptr SharedState
    dispatches: seq[DispatchSlot]

  DispatchSlot = ref object
    fn: DispatchProc

  DispatchPayload = object
    state: pointer
    slot: int

  TerminatePayload = object
    shared: ptr SharedState

var liveStates {.global.}: seq[LinuxState]

proc toShared(h: BackendHandle): ptr SharedState =
  doAssert h != nil, "viewy backend handle is nil"
  cast[ptr SharedState](h)

proc toState(h: BackendHandle): LinuxState =
  let shared = h.toShared
  for state in liveStates:
    if state.shared == shared:
      return state
  raise newException(LinuxBackendError, "viewy backend handle is not live")

proc toHandle(state: LinuxState): BackendHandle =
  cast[BackendHandle](state.shared)

proc assertUiThread(state: LinuxState) =
  when not defined(release):
    doAssert getThreadId() == state.shared.mainThreadId,
        "viewy backend operation must run on the UI thread"

proc requireOpen(state: LinuxState; op: string) =
  if state.shared.closed or state.shared.window == nil or
      state.shared.webview == nil:
    raise newException(LinuxBackendError, op & " failed: backend is closed")

proc requireOpen(shared: ptr SharedState; op: string) =
  if shared.closed or shared.window == nil or shared.webview == nil:
    raise newException(LinuxBackendError, op & " failed: backend is closed")

proc toBool(value: bool): GBoolean =
  if value: gTrue else: gFalse

proc rootState(state: LinuxState) =
  liveStates.add state

proc unrootState(state: LinuxState) =
  for i in 0 ..< liveStates.len:
    if liveStates[i] == state:
      liveStates.delete i
      return

proc closeFromUiThread(state: LinuxState) =
  let shared = state.shared
  var
    window: ptr GtkWidget
    manager: ptr WebKitUserContentManager

  acquire(shared.lock)
  if shared.closed:
    release(shared.lock)
    return

  shared.closed = true
  window = shared.window
  manager = shared.manager
  shared.window = nil
  shared.box = nil
  shared.webviewWidget = nil
  shared.webview = nil
  shared.manager = nil
  release(shared.lock)

  if window != nil:
    gtkWidgetDestroy(window)
  if manager != nil:
    gObjectUnref(manager)

proc deleteEventCb(widget: ptr GtkWidget; event: ptr GdkEvent;
    data: pointer): GBoolean {.cdecl, gcsafe.} =
  discard widget
  discard event
  let state = cast[LinuxState](data)
  {.cast(gcsafe).}:
    state.closeFromUiThread()
  gtkMainQuit()
  gTrue

proc dispatchCb(data: pointer): GBoolean {.cdecl, gcsafe.} =
  let payload = cast[ptr DispatchPayload](data)
  if payload == nil:
    return gFalse

  let state = cast[LinuxState](payload.state)
  let slotIndex = payload.slot
  deallocShared(payload)

  {.cast(gcsafe).}:
    if not state.shared.closed and slotIndex >= 0 and
        slotIndex < state.dispatches.len:
      let slot = state.dispatches[slotIndex]
      state.dispatches[slotIndex] = nil
      if slot != nil:
        try:
          slot.fn()
        except CatchableError:
          discard
    GC_unref(state)

  gFalse

proc terminateCb(data: pointer): GBoolean {.cdecl, gcsafe.} =
  let payload = cast[ptr TerminatePayload](data)
  if payload == nil:
    return gFalse

  let shared = payload.shared
  deallocShared(payload)

  {.cast(gcsafe).}:
    var window: ptr GtkWidget
    var manager: ptr WebKitUserContentManager
    acquire(shared.lock)
    if not shared.closed:
      shared.closed = true
      window = shared.window
      manager = shared.manager
      shared.window = nil
      shared.box = nil
      shared.webviewWidget = nil
      shared.webview = nil
      shared.manager = nil
    release(shared.lock)

    if window != nil:
      gtkWidgetDestroy(window)
    if manager != nil:
      gObjectUnref(manager)
  gtkMainQuit()
  gFalse

proc create(debug: bool): BackendHandle =
  var
    argc: cint
    argv: cstringArray
  if gtkInitCheck(addr argc, addr argv) == gFalse:
    raise newException(LinuxBackendError, "gtk_init_check failed")

  let manager = webkitUserContentManagerNew()
  if manager == nil:
    raise newException(LinuxBackendError, "webkit_user_content_manager_new failed")

  let window = gtkWindowNew(gtkWindowToplevel)
  if window == nil:
    gObjectUnref(manager)
    raise newException(LinuxBackendError, "gtk_window_new failed")

  let box = gtkBoxNew(gtkOrientationVertical, 0)
  if box == nil:
    gtkWidgetDestroy(window)
    gObjectUnref(manager)
    raise newException(LinuxBackendError, "gtk_box_new failed")

  let webviewWidget = webkitWebViewNewWithUserContentManager(manager)
  if webviewWidget == nil:
    gtkWidgetDestroy(window)
    gObjectUnref(manager)
    raise newException(LinuxBackendError,
        "webkit_web_view_new_with_user_content_manager failed")

  let webview = cast[ptr WebKitWebView](webviewWidget)
  let settings = webkitWebViewGetSettings(webview)
  if settings != nil:
    webkitSettingsSetEnableJavascript(settings, gTrue)
    webkitSettingsSetDeveloperExtrasEnabled(settings, debug.toBool)

  gtkContainerAdd(cast[ptr GtkContainer](window), box)
  gtkBoxPackStart(cast[ptr GtkBox](box), webviewWidget, gTrue, gTrue, 0)
  gtkWindowSetDefaultSize(cast[ptr GtkWindow](window), 800, 600)
  gtkWindowSetPosition(cast[ptr GtkWindow](window), gtkWinPosCenter)

  let shared = cast[ptr SharedState](allocShared0(sizeof(SharedState)))
  if shared == nil:
    gtkWidgetDestroy(window)
    gObjectUnref(manager)
    raise newException(LinuxBackendError, "gtk backend create failed: out of memory")
  shared[] = SharedState(
    mainThreadId: getThreadId(),
    closed: false,
    window: window,
    box: box,
    manager: manager,
    webviewWidget: webviewWidget,
    webview: webview,
  )
  initLock(shared.lock)

  let state = LinuxState(
    shared: shared,
    dispatches: @[],
  )
  rootState state

  discard gSignalConnectData(window, "delete-event", cast[pointer](
      deleteEventCb), cast[pointer](state), nil, gConnectDefault)

  state.toHandle

proc destroy(h: BackendHandle) =
  let state = h.toState
  state.assertUiThread
  state.closeFromUiThread()
  unrootState state
  # SharedState intentionally remains allocated after destroy. BackendHandle is
  # an unmanaged pointer that worker threads may still hold; keeping the closed
  # state readable lets late typed handoffs fail before touching native handles.

proc run(h: BackendHandle) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("gtk_main")
  gtkWidgetShowAll(state.shared.window)
  gtkMain()

proc terminate(h: BackendHandle) {.gcsafe.} =
  let state = block:
    {.cast(gcsafe).}:
      h.toState
  state.assertUiThread
  state.closeFromUiThread()
  gtkMainQuit()

proc dispatch(h: BackendHandle; fn: DispatchProc) {.gcsafe.} =
  let state = block:
    {.cast(gcsafe).}:
      h.toState
  if getThreadId() != state.shared.mainThreadId:
    raise newException(LinuxBackendError,
        "g_idle_add failed: closure dispatch is UI-thread only; use typed handoff")
  state.requireOpen("g_idle_add")

  let slotIndex = state.dispatches.len
  state.dispatches.add DispatchSlot(fn: fn)

  let payload = cast[ptr DispatchPayload](allocShared0(sizeof(DispatchPayload)))
  if payload == nil:
    state.dispatches[slotIndex] = nil
    raise newException(LinuxBackendError, "g_idle_add failed: out of memory")
  GC_ref(state)
  payload[] = DispatchPayload(state: cast[pointer](state), slot: slotIndex)

  if gIdleAdd(dispatchCb, payload) == 0:
    state.dispatches[slotIndex] = nil
    GC_unref(state)
    deallocShared(payload)
    raise newException(LinuxBackendError, "g_idle_add failed")

proc unsupported(op: string): ref LinuxBackendError =
  newException(LinuxBackendError, op & " is not implemented by the native Linux backend yet")

proc dispatchEval(h: BackendHandle; js: string) {.gcsafe.} =
  discard h
  discard js
  raise unsupported("dispatchEval")

proc dispatchResolve(h: BackendHandle; id: string; ok: bool;
    jsonResult: string) {.gcsafe.} =
  discard h
  discard id
  discard ok
  discard jsonResult
  raise unsupported("dispatchResolve")

proc dispatchTerminate(h: BackendHandle) {.gcsafe.} =
  let shared = h.toShared
  acquire(shared.lock)
  try:
    shared.requireOpen("g_idle_add")
    let payload = cast[ptr TerminatePayload](allocShared0(sizeof(
        TerminatePayload)))
    if payload == nil:
      raise newException(LinuxBackendError, "g_idle_add failed: out of memory")
    payload[] = TerminatePayload(shared: shared)
    if gIdleAdd(terminateCb, payload) == 0:
      deallocShared(payload)
      raise newException(LinuxBackendError, "g_idle_add failed")
  finally:
    release(shared.lock)

proc setTitle(h: BackendHandle; title: string) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("gtk_window_set_title")
  gtkWindowSetTitle(cast[ptr GtkWindow](state.shared.window), title.cstring)

proc setSize(h: BackendHandle; width, height: int; hints: WindowHints) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("gtk_window_set_default_size")
  let window = cast[ptr GtkWindow](state.shared.window)
  var geometry = GdkGeometry()
  var mask: cint
  case hints
  of whNone:
    gtkWindowSetResizable(window, gTrue)
    gtkWindowSetGeometryHints(window, nil, nil, 0)
  of whMin:
    gtkWindowSetResizable(window, gTrue)
    geometry.minWidth = cint(width)
    geometry.minHeight = cint(height)
    mask = cint(ord(gdkHintMinSize))
  of whMax:
    gtkWindowSetResizable(window, gTrue)
    geometry.maxWidth = cint(width)
    geometry.maxHeight = cint(height)
    mask = cint(ord(gdkHintMaxSize))
  of whFixed:
    gtkWindowSetResizable(window, gFalse)
    geometry.minWidth = cint(width)
    geometry.minHeight = cint(height)
    geometry.maxWidth = cint(width)
    geometry.maxHeight = cint(height)
    mask = cint(ord(gdkHintMinSize)) or cint(ord(gdkHintMaxSize))
  if mask != 0:
    gtkWindowSetGeometryHints(window, nil, addr geometry, mask)
  gtkWindowSetDefaultSize(window, cint(width), cint(height))
  gtkWindowResize(window, cint(width), cint(height))

proc navigate(h: BackendHandle; url: string) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("webkit_web_view_load_uri")
  webkitWebViewLoadUri(state.shared.webview, url.cstring)

proc setHtml(h: BackendHandle; html: string) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("webkit_web_view_load_html")
  webkitWebViewLoadHtml(state.shared.webview, html.cstring, nil)

proc eval(h: BackendHandle; js: string) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("webkit_web_view_evaluate_javascript")
  webkitWebViewEvaluateJavascript(state.shared.webview, js.cstring, int64(
      js.len), nil, nil, nil, nil, nil)

proc init(h: BackendHandle; js: string) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("webkit_user_content_manager_add_script")
  let script = webkitUserScriptNew(js.cstring, webkitUserContentInjectTopFrame,
      webkitUserScriptInjectAtDocumentStart, nil, nil)
  if script == nil:
    raise newException(LinuxBackendError, "webkit_user_script_new failed")
  webkitUserContentManagerAddScript(state.shared.manager, script)
  webkitUserScriptUnref(script)

proc bindFn(h: BackendHandle; name: string; cb: BindCallback) =
  discard h
  discard name
  if cb == nil:
    discard
  raise unsupported("bindFn")

proc unbind(h: BackendHandle; name: string) =
  discard h
  discard name
  raise unsupported("unbind")

proc resolve(h: BackendHandle; id: string; ok: bool; jsonResult: string) =
  discard h
  discard id
  discard ok
  discard jsonResult
  raise unsupported("resolve")

proc newBackend*(): Backend =
  Backend(
    create: create,
    destroy: destroy,
    run: run,
    terminate: terminate,
    dispatch: dispatch,
    dispatchEval: dispatchEval,
    dispatchResolve: dispatchResolve,
    dispatchTerminate: dispatchTerminate,
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
