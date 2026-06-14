## Native Windows backend backed by Win32 and WebView2.
##
## This slice owns the core window, message loop, and WebView2
## environment/controller lifecycle. Menus, tray, schemes, and RPC are wired by
## later Windows backend slices.

import std/[locks, os]

import ../../api
import ../../windows_webview2_pin
import ./[com, webview2, win32]

import jsony

export api

when defined(windows):
  const
    sourceDir = currentSourcePath().parentDir()
    webviewVendorDir = sourceDir / "../../../../../vendor/webview"
  {.passC: "-I" & sourceDir.}
  {.passC: "-I" & webView2SdkIncludeDir.}
  {.passC: "-I" & webviewVendorDir.}
  when defined(vcc):
    {.compile("webview2_loader.cc", "/std:c++17").}
    {.passL: "advapi32.lib ole32.lib shell32.lib shlwapi.lib version.lib".}
  else:
    {.compile("webview2_loader.cc", "-std=c++17").}
    {.passL: "-ladvapi32 -lole32 -lshell32 -lshlwapi -lversion".}

type
  WindowsBackendError* = object of CatchableError

  SharedState = object
    lock: Lock
    mainThreadId: int
    closed: bool
    comInitialized: bool
    hwnd: Hwnd
    owner: pointer

  PendingKind = enum
    pkNavigate
    pkSetHtml
    pkEval
    pkInit

  PendingOperation = object
    kind: PendingKind
    value: string

  DispatchSlot = ref object
    fn: DispatchProc

  WindowsState = ref object
    shared: ptr SharedState
    debug: bool
    environmentReady: bool
    webviewReady: bool
    handles: WebView2Handles
    pending: seq[PendingOperation]
    dispatches: seq[DispatchSlot]

  EnvHandler = object
    iface: ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler
    refs: Ulong
    state: pointer

  ControllerHandler = object
    iface: ICoreWebView2CreateCoreWebView2ControllerCompletedHandler
    refs: Ulong
    state: pointer

  HandoffKind = enum
    hkEval
    hkResolve

  SharedBytes = object
    len: int
    data: ptr UncheckedArray[char]

  HandoffPayload = object
    shared: ptr SharedState
    kind: HandoffKind
    ok: bool
    a: SharedBytes
    b: SharedBytes

  DispatchPayload = object
    state: pointer
    slot: int

const
  className = "ViewyNativeWindow"
  wmViewyDispatch = wmApp + Uint(0x101)
  wmViewyHandoff = wmApp + Uint(0x102)
  wmViewyTerminate = wmApp + Uint(0x103)
  coinitApartmentThreaded = Dword(0x2)
  eInvalidArg = Hresult(-2147024809)
  eNoInterfaceLocal = Hresult(-2147467262)

proc viewyWebView2CreateEnvironmentWithOptions(browserExecutableFolder,
    userDataFolder: Pcwstr;
    environmentOptions: ptr ICoreWebView2EnvironmentOptions;
    handler: ptr ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler
): Hresult {.importc: "viewy_webview2_create_environment_with_options",
    header: "webview2_loader.h", stdcall.}

proc toHandle(state: WindowsState): BackendHandle =
  cast[BackendHandle](state.shared)

proc toShared(h: BackendHandle): ptr SharedState =
  doAssert h != nil, "viewy backend handle is nil"
  cast[ptr SharedState](h)

proc toState(h: BackendHandle): WindowsState =
  let shared = h.toShared
  result = cast[WindowsState](shared.owner)
  if result == nil:
    raise newException(WindowsBackendError,
        "native Windows backend operation failed: backend is closed")

proc assertUiThread(state: WindowsState) =
  when not defined(release):
    doAssert getThreadId() == state.shared.mainThreadId,
        "viewy backend operation must run on the UI thread"

proc requireOpen(shared: ptr SharedState; op: string) =
  if shared.closed or shared.hwnd == nil:
    raise newException(WindowsBackendError, op & " failed: backend is closed")

proc requireOpen(state: WindowsState; op: string) =
  state.shared.requireOpen(op)

proc initSharedBytes(value: string): SharedBytes =
  result.len = value.len
  result.data = cast[ptr UncheckedArray[char]](allocShared0(value.len + 1))
  if result.data == nil:
    raise newException(WindowsBackendError,
        "native Windows handoff allocation failed")
  if value.len > 0:
    copyMem(addr result.data[0], unsafeAddr value[0], value.len)

proc free(bytes: var SharedBytes) {.gcsafe.} =
  if bytes.data != nil:
    deallocShared(bytes.data)
    bytes.data = nil
  bytes.len = 0

proc toString(bytes: SharedBytes): string =
  result = newString(bytes.len)
  if bytes.len > 0:
    copyMem(addr result[0], addr bytes.data[0], bytes.len)

proc freePayload(payload: ptr HandoffPayload) {.gcsafe.} =
  if payload != nil:
    payload.a.free()
    payload.b.free()
    deallocShared(payload)

proc newPayload(shared: ptr SharedState; kind: HandoffKind; a: string; b = "";
    ok = false): ptr HandoffPayload =
  result = cast[ptr HandoffPayload](allocShared0(sizeof(HandoffPayload)))
  if result == nil:
    raise newException(WindowsBackendError,
        "native Windows handoff allocation failed")
  try:
    result.shared = shared
    result.kind = kind
    result.ok = ok
    result.a = initSharedBytes(a)
    result.b = initSharedBytes(b)
  except CatchableError:
    freePayload(result)
    raise

proc wide(value: string): WideCString =
  newWideCString(value)

proc clientBounds(hwnd: Hwnd): Rect =
  if getClientRect(hwnd, addr result) == winFalse:
    result = Rect(left: 0, top: 0, right: 800, bottom: 600)

proc resizeWebview(state: WindowsState) =
  if state.handles.controller != nil and
      state.handles.controller.lpVtbl != nil and state.shared.hwnd != nil:
    discard state.handles.controller.lpVtbl.putBounds(
      state.handles.controller, clientBounds(state.shared.hwnd))

proc evalReady(state: WindowsState; js: string) =
  if state.handles.webview != nil and state.handles.webview.lpVtbl != nil:
    discard state.handles.webview.lpVtbl.executeScript(state.handles.webview,
        wide(js), nil)

proc applyOperation(state: WindowsState; operation: PendingOperation) =
  if state.handles.webview == nil or state.handles.webview.lpVtbl == nil:
    return
  case operation.kind
  of pkNavigate:
    discard state.handles.webview.lpVtbl.navigate(state.handles.webview,
        wide(operation.value))
  of pkSetHtml:
    discard state.handles.webview.lpVtbl.navigateToString(state.handles.webview,
        wide(operation.value))
  of pkEval:
    state.evalReady(operation.value)
  of pkInit:
    discard state.handles.webview.lpVtbl.addScriptToExecuteOnDocumentCreated(
        state.handles.webview, wide(operation.value), nil)

proc queueOrApply(state: WindowsState; kind: PendingKind; value: string) =
  state.assertUiThread
  state.requireOpen("WebView2 operation")
  let operation = PendingOperation(kind: kind, value: value)
  if state.webviewReady:
    state.applyOperation(operation)
  else:
    state.pending.add operation

proc flushPending(state: WindowsState) =
  for operation in state.pending:
    state.applyOperation(operation)
  state.pending.setLen(0)

proc closeFromUiThread(state: WindowsState) =
  let shared = state.shared
  acquire(shared.lock)
  if shared.closed:
    release(shared.lock)
    return
  shared.closed = true
  let hwnd = shared.hwnd
  shared.hwnd = nil
  release(shared.lock)

  state.handles.releaseHandles()
  state.pending.setLen(0)
  if hwnd != nil:
    discard destroyWindow(hwnd)

proc sameIid(a, b: Refiid): bool =
  if a == nil or b == nil:
    return false
  a.data1 == b.data1 and a.data2 == b.data2 and a.data3 == b.data3 and
      a.data4 == b.data4

proc queryEnv(self: ptr ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler;
    riid: Refiid; ppvObject: ptr pointer): Hresult {.stdcall.} =
  if ppvObject == nil:
    return eInvalidArg
  if sameIid(riid, addr iidIUnknown) or
      sameIid(riid, addr iidICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler):
    ppvObject[] = cast[pointer](self)
    discard cast[ptr EnvHandler](self).iface.lpVtbl.addRef(self)
    return sOk
  ppvObject[] = nil
  eNoInterfaceLocal

proc addRefEnv(self: ptr ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler
): Ulong {.stdcall.} =
  let handler = cast[ptr EnvHandler](self)
  inc handler.refs
  handler.refs

proc releaseEnv(self: ptr ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler
): Ulong {.stdcall.} =
  let handler = cast[ptr EnvHandler](self)
  let state = cast[WindowsState](handler.state)
  if handler.refs > 0:
    dec handler.refs
  result = handler.refs
  if result == 0:
    if state != nil:
      GC_unref(state)
    deallocShared(handler)

proc queryController(
    self: ptr ICoreWebView2CreateCoreWebView2ControllerCompletedHandler;
    riid: Refiid; ppvObject: ptr pointer): Hresult {.stdcall.} =
  if ppvObject == nil:
    return eInvalidArg
  if sameIid(riid, addr iidIUnknown) or
      sameIid(riid, addr iidICoreWebView2CreateCoreWebView2ControllerCompletedHandler):
    ppvObject[] = cast[pointer](self)
    discard cast[ptr ControllerHandler](self).iface.lpVtbl.addRef(self)
    return sOk
  ppvObject[] = nil
  eNoInterfaceLocal

proc addRefController(
    self: ptr ICoreWebView2CreateCoreWebView2ControllerCompletedHandler
): Ulong {.stdcall.} =
  let handler = cast[ptr ControllerHandler](self)
  inc handler.refs
  handler.refs

proc releaseControllerHandler(
    self: ptr ICoreWebView2CreateCoreWebView2ControllerCompletedHandler
): Ulong {.stdcall.} =
  let handler = cast[ptr ControllerHandler](self)
  let state = cast[WindowsState](handler.state)
  if handler.refs > 0:
    dec handler.refs
  result = handler.refs
  if result == 0:
    if state != nil:
      GC_unref(state)
    deallocShared(handler)

proc invokeController(
    self: ptr ICoreWebView2CreateCoreWebView2ControllerCompletedHandler;
    errorCode: Hresult; controller: ptr ICoreWebView2Controller
): Hresult {.stdcall.}

var controllerVtbl = CoreWebView2CreateControllerCompletedHandlerVtbl(
  queryInterface: queryController,
  addRef: addRefController,
  release: releaseControllerHandler,
  invoke: invokeController,
)

proc newControllerHandler(state: WindowsState): ptr ControllerHandler =
  result = cast[ptr ControllerHandler](allocShared0(sizeof(ControllerHandler)))
  if result == nil:
    raise newException(WindowsBackendError,
        "native Windows WebView2 controller callback allocation failed")
  result.iface.lpVtbl = addr controllerVtbl
  result.refs = 1
  result.state = cast[pointer](state)
  GC_ref(state)

proc invokeEnv(self: ptr ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler;
    errorCode: Hresult; environment: ptr ICoreWebView2Environment
): Hresult {.stdcall.} =
  let handler = cast[ptr EnvHandler](self)
  let state = cast[WindowsState](handler.state)
  defer:
    discard self.lpVtbl.release(self)
  if state == nil or state.shared.closed:
    return sOk
  if failed(errorCode) or environment == nil or environment.lpVtbl == nil:
    return sOk

  discard environment.lpVtbl.addRef(environment)
  state.handles.environment = environment
  state.environmentReady = true

  let controllerHandler = state.newControllerHandler()
  let hr = createController(environment, state.shared.hwnd,
      addr controllerHandler.iface)
  if failed(hr):
    discard controllerHandler.iface.lpVtbl.release(addr controllerHandler.iface)
    state.handles.releaseHandles()
    state.environmentReady = false
  sOk

var envVtbl = CoreWebView2CreateEnvironmentCompletedHandlerVtbl(
  queryInterface: queryEnv,
  addRef: addRefEnv,
  release: releaseEnv,
  invoke: invokeEnv,
)

proc newEnvHandler(state: WindowsState): ptr EnvHandler =
  result = cast[ptr EnvHandler](allocShared0(sizeof(EnvHandler)))
  if result == nil:
    raise newException(WindowsBackendError,
        "native Windows WebView2 environment callback allocation failed")
  result.iface.lpVtbl = addr envVtbl
  result.refs = 1
  result.state = cast[pointer](state)
  GC_ref(state)

proc invokeController(
    self: ptr ICoreWebView2CreateCoreWebView2ControllerCompletedHandler;
    errorCode: Hresult; controller: ptr ICoreWebView2Controller
): Hresult {.stdcall.} =
  let handler = cast[ptr ControllerHandler](self)
  let state = cast[WindowsState](handler.state)
  defer:
    discard self.lpVtbl.release(self)
  if state == nil or state.shared.closed:
    return sOk
  if failed(errorCode) or controller == nil:
    state.handles.releaseHandles()
    state.environmentReady = false
    return sOk

  let hr = attachController(controller, state.shared.hwnd,
      clientBounds(state.shared.hwnd), state.handles)
  if failed(hr):
    state.handles.releaseHandles()
    state.environmentReady = false
    return sOk
  let settingsHr = configureAttachedSettings(state.handles, state.debug)
  if failed(settingsHr):
    state.handles.releaseHandles()
    state.environmentReady = false
    return sOk
  state.webviewReady = true
  state.resizeWebview()
  state.flushPending()
  sOk

proc startWebView2(state: WindowsState) =
  let handler = state.newEnvHandler()
  let hr = startEnvironmentCreation(viewyWebView2CreateEnvironmentWithOptions,
      nil, addr handler.iface)
  if failed(hr):
    discard handler.iface.lpVtbl.release(addr handler.iface)
    raise newException(WindowsBackendError,
        "CreateCoreWebView2EnvironmentWithOptions failed")

proc wndProc(hwnd: Hwnd; msg: Uint; wParam: Wparam;
    lParam: Lparam): Lresult {.stdcall, gcsafe.} =
  if msg == wmNcCreate:
    let createStruct = cast[ptr CreateStructW](lParam)
    if createStruct != nil:
      discard setWindowLongPtrW(hwnd, gwlpUserData,
          cast[LongPtr](createStruct.lpCreateParams))
    return defWindowProcW(hwnd, msg, wParam, lParam)

  let state = cast[WindowsState](cast[pointer](getWindowLongPtrW(hwnd,
      gwlpUserData)))
  if state == nil:
    return defWindowProcW(hwnd, msg, wParam, lParam)

  case msg
  of wmSize:
    {.cast(gcsafe).}:
      state.resizeWebview()
    return Lresult(0)
  of wmClose:
    {.cast(gcsafe).}:
      state.closeFromUiThread()
    postQuitMessage(0)
    return Lresult(0)
  of wmDestroy:
    postQuitMessage(0)
    return Lresult(0)
  of wmViewyTerminate:
    {.cast(gcsafe).}:
      state.closeFromUiThread()
    postQuitMessage(0)
    return Lresult(0)
  of wmViewyDispatch:
    let payload = cast[ptr DispatchPayload](lParam)
    if payload != nil:
      {.cast(gcsafe).}:
        let slot = payload.slot
        deallocShared(payload)
        if slot >= 0 and slot < state.dispatches.len:
          let dispatch = state.dispatches[slot]
          state.dispatches[slot] = nil
          if dispatch != nil:
            try:
              dispatch.fn()
            except CatchableError:
              discard
    return Lresult(0)
  of wmViewyHandoff:
    var payload = cast[ptr HandoffPayload](lParam)
    if payload != nil:
      {.cast(gcsafe).}:
        let kind = payload.kind
        let a = payload.a.toString()
        let b = payload.b.toString()
        let ok = payload.ok
        freePayload(payload)
        payload = nil
        case kind
        of hkEval:
          state.queueOrApply(pkEval, a)
        of hkResolve:
          state.queueOrApply(pkEval, "if(window.__viewy&&window.__viewy._resolve)window.__viewy._resolve(" &
              a.toJson() & "," & (if ok: "true" else: "false") & "," &
              b.toJson() & ");")
    return Lresult(0)
  else:
    discard
  defWindowProcW(hwnd, msg, wParam, lParam)

var windowClassRegistered {.global.}: bool

proc registerWindowClass(instance: Hinstance) =
  if windowClassRegistered:
    return
  var wc = WndClassExW(
    cbSize: Uint(sizeof(WndClassExW)),
    style: csHRedraw or csVRedraw,
    lpfnWndProc: wndProc,
    hInstance: instance,
    hCursor: loadCursorW(nil, idcArrow()),
    lpszClassName: wide(className),
  )
  if registerClassExW(addr wc) == Atom(0):
    raise newException(WindowsBackendError, "RegisterClassExW failed")
  windowClassRegistered = true

proc create(debug: bool): BackendHandle =
  discard setProcessDpiAwarenessContext(dpiAwarenessContextPerMonitorAwareV2())
  let coHr = coInitializeEx(nil, coinitApartmentThreaded)
  if failed(Hresult(coHr)):
    raise newException(WindowsBackendError, "CoInitializeEx failed")

  let shared = cast[ptr SharedState](allocShared0(sizeof(SharedState)))
  if shared == nil:
    coUninitialize()
    raise newException(WindowsBackendError,
        "native Windows backend create failed: out of memory")
  shared.mainThreadId = getThreadId()
  shared.comInitialized = true
  initLock(shared.lock)

  let state = WindowsState(shared: shared, debug: debug, pending: @[],
      dispatches: @[])
  shared.owner = cast[pointer](state)
  GC_ref(state)

  try:
    let instance = getModuleHandleW(nil)
    registerWindowClass(instance)
    let hwnd = createWindowExW(0, wide(className), wide("Viewy"),
        wsOverlappedWindow, cwUseDefault, cwUseDefault, 800, 600, nil, nil,
        instance, cast[pointer](state))
    if hwnd == nil:
      raise newException(WindowsBackendError, "CreateWindowExW failed")
    shared.hwnd = hwnd
    state.startWebView2()
    state.toHandle
  except CatchableError:
    if shared.hwnd != nil:
      discard destroyWindow(shared.hwnd)
    shared.owner = nil
    GC_unref(state)
    deinitLock(shared.lock)
    deallocShared(shared)
    coUninitialize()
    raise

proc destroy(h: BackendHandle) =
  let shared = cast[ptr SharedState](h)
  if shared == nil:
    return
  let state = cast[WindowsState](shared.owner)
  if state == nil:
    return
  state.assertUiThread
  state.closeFromUiThread()
  state.dispatches.setLen(0)
  shared.owner = nil
  GC_unref(state)
  if shared.comInitialized:
    shared.comInitialized = false
    coUninitialize()

proc run(h: BackendHandle) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("GetMessageW")
  discard showWindow(state.shared.hwnd, swShow)
  discard updateWindow(state.shared.hwnd)
  var msg: Msg
  while getMessageW(addr msg, nil, 0, 0) != winFalse:
    discard translateMessage(addr msg)
    discard dispatchMessageW(addr msg)

proc terminate(h: BackendHandle) {.gcsafe.} =
  let state = block:
    {.cast(gcsafe).}:
      h.toState
  state.assertUiThread
  {.cast(gcsafe).}:
    state.closeFromUiThread()
  postQuitMessage(0)

proc dispatch(h: BackendHandle; fn: DispatchProc) {.gcsafe.} =
  let state = block:
    {.cast(gcsafe).}:
      h.toState
  if fn.isNil:
    return
  if getThreadId() != state.shared.mainThreadId:
    raise newException(WindowsBackendError,
        "native Windows dispatch failed: closure dispatch is UI-thread only; use typed handoff")
  state.requireOpen("PostMessageW")
  let payload = cast[ptr DispatchPayload](allocShared0(sizeof(DispatchPayload)))
  if payload == nil:
    raise newException(WindowsBackendError,
        "native Windows dispatch allocation failed")
  let slot = state.dispatches.len
  state.dispatches.add DispatchSlot(fn: fn)
  payload.state = cast[pointer](state)
  payload.slot = slot
  if postMessageW(state.shared.hwnd, wmViewyDispatch, Wparam(0),
      cast[Lparam](payload)) == winFalse:
    state.dispatches[slot] = nil
    deallocShared(payload)
    raise newException(WindowsBackendError, "PostMessageW failed")

proc postHandoff(shared: ptr SharedState; payload: ptr HandoffPayload) {.gcsafe.} =
  if postMessageW(shared.hwnd, wmViewyHandoff, Wparam(0),
      cast[Lparam](payload)) == winFalse:
    freePayload(payload)
    raise newException(WindowsBackendError, "PostMessageW failed")

proc dispatchEval(h: BackendHandle; js: string) {.gcsafe.} =
  let shared = h.toShared
  acquire(shared.lock)
  try:
    shared.requireOpen("PostMessageW")
    shared.postHandoff(newPayload(shared, hkEval, js))
  finally:
    release(shared.lock)

proc dispatchResolve(h: BackendHandle; id: string; ok: bool;
    jsonResult: string) {.gcsafe.} =
  let shared = h.toShared
  acquire(shared.lock)
  try:
    shared.requireOpen("PostMessageW")
    shared.postHandoff(newPayload(shared, hkResolve, id, jsonResult, ok))
  finally:
    release(shared.lock)

proc dispatchTerminate(h: BackendHandle) {.gcsafe.} =
  let shared = h.toShared
  acquire(shared.lock)
  try:
    shared.requireOpen("PostMessageW")
    if postMessageW(shared.hwnd, wmViewyTerminate, Wparam(0), Lparam(0)) ==
        winFalse:
      raise newException(WindowsBackendError, "PostMessageW failed")
  finally:
    release(shared.lock)

proc setTitle(h: BackendHandle; title: string) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("SetWindowTextW")
  if setWindowTextW(state.shared.hwnd, wide(title)) == winFalse:
    raise newException(WindowsBackendError, "SetWindowTextW failed")

proc setSize(h: BackendHandle; width, height: int; hints: WindowHints) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("MoveWindow")
  discard hints
  if setWindowPos(state.shared.hwnd, nil, 0, 0, Int(width), Int(height),
      swpNoMove or swpNoZOrder) == winFalse:
    raise newException(WindowsBackendError, "SetWindowPos failed")
  state.resizeWebview()

proc navigate(h: BackendHandle; url: string) =
  h.toState.queueOrApply(pkNavigate, url)

proc setHtml(h: BackendHandle; html: string) =
  h.toState.queueOrApply(pkSetHtml, html)

proc eval(h: BackendHandle; js: string) =
  h.toState.queueOrApply(pkEval, js)

proc init(h: BackendHandle; js: string) =
  h.toState.queueOrApply(pkInit, js)

proc unsupported(op: string): ref WindowsBackendError =
  newException(WindowsBackendError,
      op & " is not implemented by the native Windows backend yet")

proc bindFn(h: BackendHandle; name: string; cb: BindCallback) =
  discard h
  discard name
  doAssert cb.isNil or not cb.isNil
  raise unsupported("native Windows bind")

proc unbind(h: BackendHandle; name: string) =
  discard h
  discard name
  raise unsupported("native Windows unbind")

proc resolve(h: BackendHandle; id: string; ok: bool; jsonResult: string) =
  discard h
  discard id
  discard ok
  discard jsonResult
  raise unsupported("native Windows resolve")

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
