## Native Windows backend backed by Win32 and WebView2.
##
## This slice owns the core window, message loop, and WebView2
## environment/controller lifecycle, schemes, tray, and RPC. Menus are wired by
## later Windows backend slices.

import std/[locks, os, strutils, unicode, uri]

import ../../api
import ../../windows_webview2_pin
import ./[com, webview2, win32]
import ./ipc_bridge

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
    bindings: seq[Binding]
    schemes: seq[SchemeRegistration]
    trays: seq[TrayRegistration]
    nextTrayId: Uint
    nextMenuCommandId: Uint
    webMessageHandler: ptr WebMessageHandler
    webMessageToken: EventRegistrationToken
    webResourceHandler: ptr WebResourceHandler
    webResourceToken: EventRegistrationToken

  EnvHandler = object
    iface: ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler
    refs: Ulong
    state: pointer

  ControllerHandler = object
    iface: ICoreWebView2CreateCoreWebView2ControllerCompletedHandler
    refs: Ulong
    state: pointer

  SchemeRegistration = ref object
    scheme: string
    handler: AssetHandler

  Binding = ref object
    name: string
    cb: BindCallback

  TrayMenuCommand = object
    commandId: Uint
    id: string

  TrayRegistration = ref object
    id: string
    notifyId: Uint
    tooltip: string
    iconPath: string
    templateIconPath: string
    menu: seq[MenuItem]
    cb: MenuCallback
    hIcon: Hicon
    ownsIcon: bool
    hMenu: Hmenu
    commands: seq[TrayMenuCommand]

  WebMessageHandler = object
    iface: ICoreWebView2WebMessageReceivedEventHandler
    refs: Ulong
    state: pointer

  WebResourceHandler = object
    iface: ICoreWebView2WebResourceRequestedEventHandler
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
  virtualHostOrigin = "https://viewy.localhost"
  virtualHostFilter = "https://viewy.localhost/*"
  maxSchemeRequestBodyBytes = 10 * 1024 * 1024
  trayMenuCommandMin = Uint(1000)
  trayMenuCommandMax = Uint(0xEFFF)
  wmViewyDispatch = wmApp + Uint(0x101)
  wmViewyHandoff = wmApp + Uint(0x102)
  wmViewyTerminate = wmApp + Uint(0x103)
  wmViewyTray = wmApp + Uint(0x104)
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

proc wideToString(value: Lpwstr): string =
  if value == nil:
    ""
  else:
    $value

proc freeWide(value: var Lpwstr) =
  if value != nil:
    coTaskMemFree(cast[pointer](value))
    value = nil

proc releaseStream(stream: ptr IStream) =
  if stream != nil and stream.lpVtbl != nil:
    discard stream.lpVtbl.release(stream)

proc releaseWebResourceResponse(response: ptr ICoreWebView2WebResourceResponse) =
  if response != nil and response.lpVtbl != nil:
    discard response.lpVtbl.release(response)

proc releaseRequest(request: ptr ICoreWebView2WebResourceRequest) =
  if request != nil and request.lpVtbl != nil:
    discard request.lpVtbl.release(request)

proc releaseHeaders(headers: ptr ICoreWebView2HttpRequestHeaders) =
  if headers != nil and headers.lpVtbl != nil:
    discard headers.lpVtbl.release(headers)

proc releaseHeaderIterator(
    headerIterator: ptr ICoreWebView2HttpHeadersCollectionIterator) =
  if headerIterator != nil and headerIterator.lpVtbl != nil:
    discard headerIterator.lpVtbl.release(headerIterator)

proc readStream(stream: ptr IStream; byteLimit: int): string =
  if stream == nil or stream.lpVtbl == nil or stream.lpVtbl.read == nil:
    return ""
  var buffer: array[4096, char]
  var remaining = byteLimit
  while remaining > 0:
    let chunk = min(buffer.len, remaining)
    var count: Ulong
    let hr = stream.lpVtbl.read(stream, addr buffer[0], Ulong(chunk),
        addr count)
    if failed(hr):
      raise newException(WindowsBackendError, "IStream.Read failed")
    if count == 0:
      return
    let oldLen = result.len
    result.setLen(oldLen + count.int)
    copyMem(addr result[oldLen], addr buffer[0], count.int)
    remaining.dec count.int
  var extra: Ulong
  let hr = stream.lpVtbl.read(stream, addr buffer[0], Ulong(1), addr extra)
  if succeeded(hr) and extra > 0:
    raise newException(WindowsBackendError,
        "native Windows scheme request body exceeded maximum size")

proc hasHeader(headers: openArray[Header]; name: string): bool =
  for header in headers:
    if cmpIgnoreCase(header.name, name) == 0:
      return true

proc reasonForStatus(status: int; statusText: string): string =
  if statusText.len > 0:
    statusText
  elif status == 500:
    "Internal Server Error"
  elif status == 404:
    "Not Found"
  elif status == 400:
    "Bad Request"
  elif status == 206:
    "Partial Content"
  elif status == 416:
    "Range Not Satisfiable"
  else:
    "OK"

proc responseHeaders(response: AssetResponse): string =
  var headers = response.headers
  if response.mimeType.len > 0 and not headers.hasHeader("Content-Type"):
    headers.add Header((name: "Content-Type", value: response.mimeType))
  if not headers.hasHeader("Content-Length"):
    headers.add Header((name: "Content-Length", value: $response.body.len))
  for header in headers:
    if header.name.len > 0 and header.value.len > 0:
      result.add header.name & ": " & header.value & "\r\n"

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

proc findScheme(state: WindowsState; scheme: string): SchemeRegistration =
  for registration in state.schemes:
    if registration.scheme == scheme:
      return registration

proc hasScheme(state: WindowsState; scheme: string): bool =
  state.findScheme(scheme) != nil

proc findBinding(state: WindowsState; name: string): Binding =
  for binding in state.bindings:
    if binding.name == name:
      return binding

proc removeBinding(state: WindowsState; name: string) =
  for i in 0 ..< state.bindings.len:
    if state.bindings[i].name == name:
      state.bindings.delete i
      return

proc findTray(state: WindowsState; id: string): TrayRegistration =
  for tray in state.trays:
    if tray.id == id:
      return tray

proc findTrayByNotifyId(state: WindowsState; notifyId: Uint): TrayRegistration =
  for tray in state.trays:
    if tray.notifyId == notifyId:
      return tray

proc findTrayCommand(state: WindowsState; commandId: Uint): tuple[
    tray: TrayRegistration; id: string] =
  for tray in state.trays:
    for command in tray.commands:
      if command.commandId == commandId:
        return (tray, command.id)

proc removeTray(state: WindowsState; id: string) =
  for i in 0 ..< state.trays.len:
    if state.trays[i].id == id:
      state.trays.delete i
      return

proc copyWide(dest: var openArray[Utf16Char]; value: string) =
  if dest.len == 0:
    return
  for i in 0 ..< dest.len:
    dest[i] = Utf16Char(0)
  var i = 0
  for rune in value.runes:
    let codepoint = int32(rune)
    if codepoint <= 0xFFFF:
      if i >= dest.len - 1:
        break
      dest[i] = Utf16Char(codepoint)
      inc i
    else:
      if i >= dest.len - 2:
        break
      let scalar = codepoint - 0x10000
      dest[i] = Utf16Char(0xD800 + (scalar shr 10))
      dest[i + 1] = Utf16Char(0xDC00 + (scalar and 0x3FF))
      inc i, 2

proc loadTrayIcon(options: TrayOptions): tuple[hIcon: Hicon; ownsIcon: bool] =
  let path =
    if options.iconPath.len > 0:
      options.iconPath
    else:
      options.templateIconPath
  if path.len > 0:
    if not fileExists(path):
      raise newException(WindowsBackendError,
          "native Windows tray icon load failed: missing file " & path)
    let icon = cast[Hicon](loadImageW(nil, wide(path), imageIcon, 0, 0,
        lrLoadFromFile))
    if icon == nil:
      raise newException(WindowsBackendError,
          "native Windows tray icon load failed: LoadImageW failed")
    return (icon, true)
  let icon = loadIconW(nil, idiApplication())
  if icon == nil:
    raise newException(WindowsBackendError,
        "native Windows tray icon load failed: LoadIconW failed")
  (icon, false)

proc releaseTrayResources(tray: TrayRegistration) =
  if tray == nil:
    return
  if tray.hMenu != nil:
    discard destroyMenu(tray.hMenu)
    tray.hMenu = nil
  tray.commands.setLen(0)
  if tray.hIcon != nil and tray.ownsIcon:
    discard destroyIcon(tray.hIcon)
  tray.hIcon = nil
  tray.ownsIcon = false

proc notifyData(state: WindowsState; tray: TrayRegistration;
    flags: Uint): NotifyIconDataW =
  result.cbSize = Dword(sizeof(NotifyIconDataW))
  result.hWnd = state.shared.hwnd
  result.uID = tray.notifyId
  result.uFlags = flags
  result.uCallbackMessage = wmViewyTray
  result.hIcon = tray.hIcon
  copyWide(result.szTip, tray.tooltip)

proc shellNotify(state: WindowsState; message: Dword; tray: TrayRegistration;
    flags: Uint; op: string) =
  var data = state.notifyData(tray, flags)
  if shellNotifyIconW(message, addr data) == winFalse:
    raise newException(WindowsBackendError, "native Windows tray " & op &
        " failed: Shell_NotifyIconW failed")

proc tryShellNotify(state: WindowsState; message: Dword; tray: TrayRegistration;
    flags: Uint): bool =
  var data = state.notifyData(tray, flags)
  shellNotifyIconW(message, addr data) != winFalse

proc restoreTrayIcons(state: WindowsState) =
  for tray in state.trays:
    discard state.tryShellNotify(nimAdd, tray, nifMessage or nifIcon or nifTip)

proc modifyTrayIcon(state: WindowsState; tray: TrayRegistration) =
  if state.tryShellNotify(nimModify, tray, nifMessage or nifIcon or nifTip):
    return
  if state.tryShellNotify(nimAdd, tray, nifMessage or nifIcon or nifTip):
    return
  raise newException(WindowsBackendError,
      "native Windows tray update failed: Shell_NotifyIconW failed")

proc hasMenuCommand(state: WindowsState; commandId: Uint): bool =
  for tray in state.trays:
    for command in tray.commands:
      if command.commandId == commandId:
        return true

proc nextMenuCommandId(state: WindowsState): Uint =
  var candidate =
    if state.nextMenuCommandId >= trayMenuCommandMin and
        state.nextMenuCommandId <= trayMenuCommandMax:
      state.nextMenuCommandId
    else:
      trayMenuCommandMin
  let commandCount = int(trayMenuCommandMax - trayMenuCommandMin + 1)
  for _ in 0 ..< commandCount:
    if not state.hasMenuCommand(candidate):
      result = candidate
      if candidate == trayMenuCommandMax:
        state.nextMenuCommandId = trayMenuCommandMin
      else:
        state.nextMenuCommandId = candidate + Uint(1)
      return
    if candidate == trayMenuCommandMax:
      candidate = trayMenuCommandMin
    else:
      inc candidate
  raise newException(WindowsBackendError,
      "native Windows tray menu command id space exhausted")

proc menuFlags(item: MenuItem): Uint =
  result = mfString
  if not item.enabled:
    result = result or mfGrayed or mfDisabled
  if item.checked:
    result = result or mfChecked

proc menuLabel(item: MenuItem): string =
  result = item.label
  if result.len == 0:
    result = item.id
  if item.accelerator.len > 0:
    result.add "\t"
    result.add item.accelerator

proc appendMenuItems(state: WindowsState; tray: TrayRegistration; menu: Hmenu;
    items: openArray[MenuItem])

proc appendMenuItem(state: WindowsState; tray: TrayRegistration; menu: Hmenu;
    item: MenuItem) =
  case item.kind
  of miSeparator:
    if appendMenuW(menu, mfSeparator, UintPtr(0), nil) == winFalse:
      raise newException(WindowsBackendError,
          "native Windows tray menu append failed")
  of miSubmenu:
    let submenu = createPopupMenu()
    if submenu == nil:
      raise newException(WindowsBackendError,
          "native Windows tray submenu create failed")
    var attached = false
    try:
      state.appendMenuItems(tray, submenu, item.children)
      if appendMenuW(menu, item.menuFlags or mfPopup, cast[UintPtr](submenu),
          wide(item.menuLabel)) == winFalse:
        raise newException(WindowsBackendError,
            "native Windows tray submenu append failed")
      attached = true
    except CatchableError:
      if not attached:
        discard destroyMenu(submenu)
      raise
  of miCommand, miCheckbox, miRadio:
    let commandId = state.nextMenuCommandId()
    tray.commands.add TrayMenuCommand(commandId: commandId, id: item.id)
    if appendMenuW(menu, item.menuFlags, UintPtr(commandId),
        wide(item.menuLabel)) == winFalse:
      raise newException(WindowsBackendError,
          "native Windows tray menu item append failed")

proc appendMenuItems(state: WindowsState; tray: TrayRegistration; menu: Hmenu;
    items: openArray[MenuItem]) =
  for item in items:
    state.appendMenuItem(tray, menu, item)

proc buildTrayMenu(state: WindowsState; tray: TrayRegistration;
    items: openArray[MenuItem]): Hmenu =
  if items.len == 0:
    return nil
  result = createPopupMenu()
  if result == nil:
    raise newException(WindowsBackendError,
        "native Windows tray menu create failed")
  try:
    state.appendMenuItems(tray, result, items)
  except CatchableError:
    discard destroyMenu(result)
    result = nil
    tray.commands.setLen(0)
    raise

proc showTrayMenu(state: WindowsState; tray: TrayRegistration) =
  if tray == nil or tray.hMenu == nil:
    return
  var point: Point
  if getCursorPos(addr point) == winFalse:
    point = Point(x: 0, y: 0)
  discard setForegroundWindow(state.shared.hwnd)
  discard trackPopupMenu(tray.hMenu, tpmRightButton, Int(point.x),
      Int(point.y), 0, state.shared.hwnd, nil)

proc deleteTrayIcon(state: WindowsState; tray: TrayRegistration) =
  if state.shared.hwnd == nil or tray == nil:
    return
  var data = state.notifyData(tray, Uint(0))
  discard shellNotifyIconW(nimDelete, addr data)

proc clearTrays(state: WindowsState) =
  for tray in state.trays:
    state.deleteTrayIcon(tray)
    tray.releaseTrayResources()
  state.trays.setLen(0)

proc releaseWebMessageHandler(state: WindowsState)

proc ensureWebMessageHandler(state: WindowsState)

proc releaseWebResourceHandler(state: WindowsState)

proc ensureWebResourceHandler(state: WindowsState)

proc closeFromUiThread(state: WindowsState) =
  let shared = state.shared
  acquire(shared.lock)
  if shared.closed:
    release(shared.lock)
    return
  shared.closed = true
  let hwnd = shared.hwnd
  release(shared.lock)

  state.clearTrays()
  acquire(shared.lock)
  if shared.hwnd == hwnd:
    shared.hwnd = nil
  release(shared.lock)
  state.releaseWebMessageHandler()
  state.releaseWebResourceHandler()
  state.handles.releaseHandles()
  state.pending.setLen(0)
  state.bindings.setLen(0)
  state.schemes.setLen(0)
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

proc queryWebMessage(self: ptr ICoreWebView2WebMessageReceivedEventHandler;
    riid: Refiid; ppvObject: ptr pointer): Hresult {.stdcall.} =
  if ppvObject == nil:
    return eInvalidArg
  if sameIid(riid, addr iidIUnknown) or
      sameIid(riid, addr iidICoreWebView2WebMessageReceivedEventHandler):
    ppvObject[] = cast[pointer](self)
    discard cast[ptr WebMessageHandler](self).iface.lpVtbl.addRef(self)
    return sOk
  ppvObject[] = nil
  eNoInterfaceLocal

proc addRefWebMessage(self: ptr ICoreWebView2WebMessageReceivedEventHandler
): Ulong {.stdcall.} =
  let handler = cast[ptr WebMessageHandler](self)
  inc handler.refs
  handler.refs

proc releaseWebMessage(self: ptr ICoreWebView2WebMessageReceivedEventHandler
): Ulong {.stdcall.} =
  let handler = cast[ptr WebMessageHandler](self)
  let state = cast[WindowsState](handler.state)
  if handler.refs > 0:
    dec handler.refs
  result = handler.refs
  if result == 0:
    if state != nil:
      GC_unref(state)
    deallocShared(handler)

proc queryWebResource(
    self: ptr ICoreWebView2WebResourceRequestedEventHandler;
    riid: Refiid; ppvObject: ptr pointer): Hresult {.stdcall.} =
  if ppvObject == nil:
    return eInvalidArg
  if sameIid(riid, addr iidIUnknown) or
      sameIid(riid, addr iidICoreWebView2WebResourceRequestedEventHandler):
    ppvObject[] = cast[pointer](self)
    discard cast[ptr WebResourceHandler](self).iface.lpVtbl.addRef(self)
    return sOk
  ppvObject[] = nil
  eNoInterfaceLocal

proc addRefWebResource(self: ptr ICoreWebView2WebResourceRequestedEventHandler
): Ulong {.stdcall.} =
  let handler = cast[ptr WebResourceHandler](self)
  inc handler.refs
  handler.refs

proc releaseWebResource(self: ptr ICoreWebView2WebResourceRequestedEventHandler
): Ulong {.stdcall.} =
  let handler = cast[ptr WebResourceHandler](self)
  let state = cast[WindowsState](handler.state)
  if handler.refs > 0:
    dec handler.refs
  result = handler.refs
  if result == 0:
    if state != nil:
      GC_unref(state)
    deallocShared(handler)

proc webMessageString(args: ptr ICoreWebView2WebMessageReceivedEventArgs): string =
  if args == nil or args.lpVtbl == nil or
      args.lpVtbl.tryGetWebMessageAsString == nil:
    return ""
  var message: Lpwstr
  if succeeded(args.lpVtbl.tryGetWebMessageAsString(args, addr message)):
    result = message.wideToString
  freeWide(message)

proc webMessageReceived(
    self: ptr ICoreWebView2WebMessageReceivedEventHandler;
    sender: ptr ICoreWebView2; args: ptr ICoreWebView2WebMessageReceivedEventArgs
): Hresult {.stdcall.} =
  discard sender
  let state = cast[WindowsState](cast[ptr WebMessageHandler](self).state)
  if state == nil or state.shared.closed:
    return sOk
  try:
    let message = args.webMessageString
    if message.len == 0:
      return sOk
    let payload = parseWindowsWebMessage(message)
    let binding = state.findBinding(payload.name)
    if binding != nil and not binding.cb.isNil:
      binding.cb(payload.id, payload.jsonArgs)
  except CatchableError:
    discard
  sOk

var webMessageVtbl = CoreWebView2WebMessageReceivedEventHandlerVtbl(
  queryInterface: queryWebMessage,
  addRef: addRefWebMessage,
  release: releaseWebMessage,
  invoke: webMessageReceived,
)

proc newWebMessageHandler(state: WindowsState): ptr WebMessageHandler =
  result = cast[ptr WebMessageHandler](allocShared0(sizeof(WebMessageHandler)))
  if result == nil:
    raise newException(WindowsBackendError,
        "native Windows WebMessageReceived callback allocation failed")
  result.iface.lpVtbl = addr webMessageVtbl
  result.refs = 1
  result.state = cast[pointer](state)
  GC_ref(state)

proc ensureWebMessageHandler(state: WindowsState) =
  if state.webMessageHandler != nil or not state.webviewReady:
    return
  if state.handles.webview == nil or state.handles.webview.lpVtbl == nil:
    return
  let handler = state.newWebMessageHandler()
  var token: EventRegistrationToken
  let hr = state.handles.webview.lpVtbl.addWebMessageReceived(
      state.handles.webview, addr handler.iface, addr token)
  if failed(hr):
    discard handler.iface.lpVtbl.release(addr handler.iface)
    raise newException(WindowsBackendError,
        "ICoreWebView2.add_WebMessageReceived failed")
  state.webMessageHandler = handler
  state.webMessageToken = token

proc releaseWebMessageHandler(state: WindowsState) =
  if state.webMessageHandler == nil:
    return
  if state.handles.webview != nil and state.handles.webview.lpVtbl != nil:
    discard state.handles.webview.lpVtbl.removeWebMessageReceived(
        state.handles.webview, state.webMessageToken)
  discard state.webMessageHandler.iface.lpVtbl.release(
      addr state.webMessageHandler.iface)
  state.webMessageHandler = nil
  state.webMessageToken = EventRegistrationToken()

proc requestHeaders(request: ptr ICoreWebView2WebResourceRequest): seq[Header] =
  if request == nil or request.lpVtbl == nil:
    return @[]
  var headers: ptr ICoreWebView2HttpRequestHeaders
  if failed(request.lpVtbl.getHeaders(request, addr headers)) or
      headers == nil or headers.lpVtbl == nil:
    return @[]
  defer:
    releaseHeaders(headers)

  var headerIterator: ptr ICoreWebView2HttpHeadersCollectionIterator
  if failed(headers.lpVtbl.getIterator(headers, addr headerIterator)) or
      headerIterator == nil or headerIterator.lpVtbl == nil:
    return @[]
  defer:
    releaseHeaderIterator(headerIterator)

  var hasCurrent = winFalse
  while succeeded(headerIterator.lpVtbl.getHasCurrentHeader(headerIterator,
      addr hasCurrent)) and hasCurrent != winFalse:
    var
      name: Lpwstr
      value: Lpwstr
    if succeeded(headerIterator.lpVtbl.getCurrentHeader(headerIterator,
        addr name, addr value)):
      result.add Header((name: name.wideToString, value: value.wideToString))
    freeWide(name)
    freeWide(value)
    var hasNext = winFalse
    if failed(headerIterator.lpVtbl.moveNext(headerIterator, addr hasNext)) or
        hasNext == winFalse:
      break

proc requestUri(request: ptr ICoreWebView2WebResourceRequest): string =
  var uri: Lpwstr
  if request != nil and request.lpVtbl != nil and
      succeeded(request.lpVtbl.getUri(request, addr uri)):
    result = uri.wideToString
  freeWide(uri)

proc requestMethod(request: ptr ICoreWebView2WebResourceRequest): string =
  var methodName: Lpwstr
  if request != nil and request.lpVtbl != nil and
      succeeded(request.lpVtbl.getMethod(request, addr methodName)):
    result = methodName.wideToString.toUpperAscii
  freeWide(methodName)
  if result.len == 0:
    result = "GET"

proc requestBody(request: ptr ICoreWebView2WebResourceRequest;
    httpMethod: string): string =
  if httpMethod in ["GET", "HEAD"] or request == nil or request.lpVtbl == nil:
    return ""
  var stream: ptr IStream
  if failed(request.lpVtbl.getContent(request, addr stream)) or stream == nil:
    return ""
  try:
    result = stream.readStream(maxSchemeRequestBodyBytes)
  finally:
    releaseStream(stream)

proc schemeTextResponse(status: int; statusText, body: string): AssetResponse =
  AssetResponse(
    status: status,
    statusText: statusText,
    mimeType: "text/plain; charset=utf-8",
    headers: @[(name: "Cache-Control", value: "no-store")],
    body: body,
  )

proc makeStream(body: string): ptr IStream =
  let bodyPtr =
    if body.len == 0:
      nil
    else:
      cast[pointer](unsafeAddr body[0])
  cast[ptr IStream](shCreateMemStream(bodyPtr, Uint(body.len)))

proc applyWebResourceResponse(state: WindowsState;
    args: ptr ICoreWebView2WebResourceRequestedEventArgs;
    response: AssetResponse) =
  if state.handles.environment == nil or
      state.handles.environment.lpVtbl == nil or args == nil or
      args.lpVtbl == nil:
    return
  let status = if response.status >= 100: response.status else: 500
  let reason = reasonForStatus(status, response.statusText)
  let stream = response.body.makeStream()
  var webResponse: ptr ICoreWebView2WebResourceResponse
  let hr = createWebResourceResponse(state.handles.environment, stream,
      Int(status), wide(reason), wide(response.responseHeaders),
          addr webResponse)
  releaseStream(stream)
  if failed(hr) or webResponse == nil:
    return
  discard args.lpVtbl.putResponse(args, webResponse)
  releaseWebResourceResponse(webResponse)

proc webResourceRequested(
    self: ptr ICoreWebView2WebResourceRequestedEventHandler;
    sender: ptr ICoreWebView2; args: ptr ICoreWebView2WebResourceRequestedEventArgs
): Hresult {.stdcall.} =
  discard sender
  let state = cast[WindowsState](cast[ptr WebResourceHandler](self).state)
  if state == nil or state.shared.closed:
    return sOk
  try:
    var request: ptr ICoreWebView2WebResourceRequest
    if args == nil or args.lpVtbl == nil or failed(args.lpVtbl.getRequest(args,
        addr request)) or request == nil:
      state.applyWebResourceResponse(args, schemeTextResponse(400,
          "Bad Request", "bad request"))
      return sOk
    defer:
      releaseRequest(request)

    let parsed = parseUri(request.requestUri)
    let schemeName =
      if parsed.scheme == "https" and parsed.hostname == "viewy.localhost":
        "viewy"
      else:
        parsed.scheme
    let registration = state.findScheme(schemeName)
    if registration == nil:
      state.applyWebResourceResponse(args, schemeTextResponse(404, "Not Found",
          "not found"))
      return sOk

    let path = if parsed.path.len == 0: "/" else: parsed.path
    let httpMethod = request.requestMethod
    let assetRequest = AssetRequest(
      scheme: registration.scheme,
      httpMethod: httpMethod,
      path: path,
      query: parsed.query,
      headers: request.requestHeaders,
      body: request.requestBody(httpMethod),
    )
    let response = registration.handler(assetRequest)
    state.applyWebResourceResponse(args, response)
  except CatchableError:
    state.applyWebResourceResponse(args, schemeTextResponse(500,
        "Internal Server Error", "internal server error"))
  sOk

var webResourceVtbl = CoreWebView2WebResourceRequestedEventHandlerVtbl(
  queryInterface: queryWebResource,
  addRef: addRefWebResource,
  release: releaseWebResource,
  invoke: webResourceRequested,
)

proc newWebResourceHandler(state: WindowsState): ptr WebResourceHandler =
  result = cast[ptr WebResourceHandler](allocShared0(sizeof(
      WebResourceHandler)))
  if result == nil:
    raise newException(WindowsBackendError,
        "native Windows WebResourceRequested callback allocation failed")
  result.iface.lpVtbl = addr webResourceVtbl
  result.refs = 1
  result.state = cast[pointer](state)
  GC_ref(state)

proc ensureWebResourceHandler(state: WindowsState) =
  if state.webResourceHandler != nil or not state.webviewReady:
    return
  if state.handles.webview == nil or state.handles.webview.lpVtbl == nil:
    return
  let handler = state.newWebResourceHandler()
  var token: EventRegistrationToken
  var hr = state.handles.webview.lpVtbl.addWebResourceRequested(
      state.handles.webview, addr handler.iface, addr token)
  if failed(hr):
    discard handler.iface.lpVtbl.release(addr handler.iface)
    raise newException(WindowsBackendError,
        "ICoreWebView2.add_WebResourceRequested failed")
  hr = state.handles.webview.lpVtbl.addWebResourceRequestedFilter(
      state.handles.webview, wide(virtualHostFilter), wrcAll)
  if failed(hr):
    discard state.handles.webview.lpVtbl.removeWebResourceRequested(
        state.handles.webview, token)
    discard handler.iface.lpVtbl.release(addr handler.iface)
    raise newException(WindowsBackendError,
        "ICoreWebView2.add_WebResourceRequestedFilter failed")
  state.webResourceHandler = handler
  state.webResourceToken = token

proc releaseWebResourceHandler(state: WindowsState) =
  if state.webResourceHandler == nil:
    return
  if state.handles.webview != nil and state.handles.webview.lpVtbl != nil:
    discard state.handles.webview.lpVtbl.removeWebResourceRequested(
        state.handles.webview, state.webResourceToken)
    discard state.handles.webview.lpVtbl.removeWebResourceRequestedFilter(
        state.handles.webview, wide(virtualHostFilter), wrcAll)
  discard state.webResourceHandler.iface.lpVtbl.release(
      addr state.webResourceHandler.iface)
  state.webResourceHandler = nil
  state.webResourceToken = EventRegistrationToken()

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
  if state.bindings.len > 0:
    state.ensureWebMessageHandler()
  if state.schemes.len > 0:
    state.ensureWebResourceHandler()
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

var taskbarCreatedMessage {.global.}: Uint

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

  if taskbarCreatedMessage != Uint(0) and msg == taskbarCreatedMessage:
    {.cast(gcsafe).}:
      state.restoreTrayIcons()
    return Lresult(0)

  case msg
  of wmSize:
    {.cast(gcsafe).}:
      state.resizeWebview()
    return Lresult(0)
  of wmCommand:
    let commandId = Uint(wParam and Wparam(0xFFFF))
    {.cast(gcsafe).}:
      let command = state.findTrayCommand(commandId)
      if command.tray != nil and not command.tray.cb.isNil:
        try:
          command.tray.cb(command.id)
        except CatchableError:
          discard
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
  of wmViewyTray:
    {.cast(gcsafe).}:
      let tray = state.findTrayByNotifyId(Uint(wParam))
      if tray != nil:
        case Uint(lParam)
        of wmLButtonUp:
          if not tray.cb.isNil:
            try:
              tray.cb(tray.id)
            except CatchableError:
              discard
        of wmRButtonUp:
          state.showTrayMenu(tray)
        else:
          discard
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
          state.queueOrApply(pkEval, windowsResolveScript(a, ok, b))
    return Lresult(0)
  else:
    discard
  defWindowProcW(hwnd, msg, wParam, lParam)

var windowClassRegistered {.global.}: bool

proc registerWindowClass(instance: Hinstance) =
  if taskbarCreatedMessage == Uint(0):
    taskbarCreatedMessage = registerWindowMessageW(wide("TaskbarCreated"))
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

proc postHandoff(shared: ptr SharedState;
    payload: ptr HandoffPayload) {.gcsafe.} =
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
  let target =
    if url.startsWith("viewy://app/"):
      virtualHostOrigin & "/" & url["viewy://app/".len .. ^1]
    elif url == "viewy://app":
      virtualHostOrigin & "/"
    else:
      url
  h.toState.queueOrApply(pkNavigate, target)

proc setHtml(h: BackendHandle; html: string) =
  h.toState.queueOrApply(pkSetHtml, html)

proc eval(h: BackendHandle; js: string) =
  h.toState.queueOrApply(pkEval, js)

proc init(h: BackendHandle; js: string) =
  h.toState.queueOrApply(pkInit, js)

proc bindFn(h: BackendHandle; name: string; cb: BindCallback) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("native Windows bind")
  if state.findBinding(name) != nil:
    raise newException(WindowsBackendError,
        "native Windows bind failed: duplicate binding " & name)
  if cb.isNil:
    raise newException(WindowsBackendError,
        "native Windows bind failed: nil callback")
  state.bindings.add Binding(name: name, cb: cb)
  state.ensureWebMessageHandler()
  let script = windowsBindScript(name)
  state.queueOrApply(pkInit, script)
  state.queueOrApply(pkEval, script)

proc unbind(h: BackendHandle; name: string) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("native Windows unbind")
  state.removeBinding(name)
  let script = windowsUnbindScript(name)
  state.queueOrApply(pkInit, script)
  state.queueOrApply(pkEval, script)

proc resolve(h: BackendHandle; id: string; ok: bool; jsonResult: string) =
  h.toState.queueOrApply(pkEval, windowsResolveScript(id, ok, jsonResult))

proc registerScheme(h: BackendHandle; scheme: string; handler: AssetHandler) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("native Windows scheme registration")
  if scheme.len == 0:
    raise newException(WindowsBackendError,
        "native Windows scheme registration failed: empty scheme")
  if scheme != "viewy":
    raise newException(WindowsBackendError,
        "native Windows scheme registration failed: only viewy is supported")
  if handler.isNil:
    raise newException(WindowsBackendError,
        "native Windows scheme registration failed: nil handler")
  if state.hasScheme(scheme):
    raise newException(WindowsBackendError,
        "native Windows scheme registration failed: duplicate scheme " & scheme)
  state.schemes.add SchemeRegistration(scheme: scheme, handler: handler)
  state.ensureWebResourceHandler()

proc trayCreate(h: BackendHandle; options: TrayOptions; cb: MenuCallback) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("native Windows tray create")
  if options.id.len == 0:
    raise newException(WindowsBackendError,
        "native Windows tray create failed: empty tray id")
  if cb.isNil:
    raise newException(WindowsBackendError,
        "native Windows tray create failed: nil callback")
  if state.findTray(options.id) != nil:
    raise newException(WindowsBackendError,
        "native Windows tray create failed: duplicate tray id " & options.id)

  let icon = options.loadTrayIcon()
  if state.nextTrayId == 0:
    state.nextTrayId = Uint(1)
  let tray = TrayRegistration(
    id: options.id,
    notifyId: state.nextTrayId,
    tooltip: options.tooltip,
    iconPath: options.iconPath,
    templateIconPath: options.templateIconPath,
    menu: options.menu,
    cb: cb,
    hIcon: icon.hIcon,
    ownsIcon: icon.ownsIcon,
  )
  inc state.nextTrayId
  try:
    tray.hMenu = state.buildTrayMenu(tray, options.menu)
    state.shellNotify(nimAdd, tray, nifMessage or nifIcon or nifTip, "create")
    state.trays.add tray
  except CatchableError:
    state.deleteTrayIcon(tray)
    tray.releaseTrayResources()
    raise

proc trayUpdate(h: BackendHandle; id: string; options: TrayOptions) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("native Windows tray update")
  if id.len == 0:
    raise newException(WindowsBackendError,
        "native Windows tray update failed: empty tray id")
  let tray = state.findTray(id)
  if tray == nil:
    raise newException(WindowsBackendError,
        "native Windows tray update failed: unknown tray id " & id)

  let icon = options.loadTrayIcon()
  let oldIcon = tray.hIcon
  let oldOwnsIcon = tray.ownsIcon
  let oldMenu = tray.hMenu
  let oldCommands = tray.commands
  let oldTooltip = tray.tooltip
  let oldIconPath = tray.iconPath
  let oldTemplateIconPath = tray.templateIconPath
  let oldMenuItems = tray.menu
  tray.hIcon = icon.hIcon
  tray.ownsIcon = icon.ownsIcon
  tray.tooltip = options.tooltip
  tray.iconPath = options.iconPath
  tray.templateIconPath = options.templateIconPath
  tray.menu = options.menu
  tray.hMenu = nil
  tray.commands = @[]
  try:
    tray.hMenu = state.buildTrayMenu(tray, options.menu)
    state.modifyTrayIcon(tray)
    if oldMenu != nil:
      discard destroyMenu(oldMenu)
    if oldIcon != nil and oldOwnsIcon:
      discard destroyIcon(oldIcon)
  except CatchableError:
    if tray.hMenu != nil:
      discard destroyMenu(tray.hMenu)
    if tray.hIcon != nil and tray.ownsIcon:
      discard destroyIcon(tray.hIcon)
    tray.hIcon = oldIcon
    tray.ownsIcon = oldOwnsIcon
    tray.hMenu = oldMenu
    tray.commands = oldCommands
    tray.tooltip = oldTooltip
    tray.iconPath = oldIconPath
    tray.templateIconPath = oldTemplateIconPath
    tray.menu = oldMenuItems
    raise

proc trayDestroy(h: BackendHandle; id: string) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("native Windows tray destroy")
  if id.len == 0:
    raise newException(WindowsBackendError,
        "native Windows tray destroy failed: empty tray id")
  let tray = state.findTray(id)
  if tray == nil:
    raise newException(WindowsBackendError,
        "native Windows tray destroy failed: unknown tray id " & id)
  state.deleteTrayIcon(tray)
  tray.releaseTrayResources()
  state.removeTray(id)

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
    caps: {capScheme, capTray},
    registerSchemeImpl: registerScheme,
    trayCreateImpl: trayCreate,
    trayUpdateImpl: trayUpdate,
    trayDestroyImpl: trayDestroy,
  )
