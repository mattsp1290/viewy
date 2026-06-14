## Native Linux backend backed by GTK3 and WebKitGTK 4.1.
##
## This module owns the core window/webview lifecycle and JavaScript binding
## bridge. Higher-level native features such as custom schemes, menus, and tray
## integration are implemented by later backend slices.

import std/[locks, strutils, uri]

import ../../api
import ./webkitgtk_ffi

import jsony
import zippy

export api

const nativeHandlerName = "viewy"
const maxSchemeRequestBodyBytes = 10 * 1024 * 1024

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

  SchemeRegistration = ref object
    scheme: string
    handler: AssetHandler

  Binding = ref object
    name: string
    cb: BindCallback

  LinuxState = ref object
    shared: ptr SharedState
    bindings: seq[Binding]
    schemes: seq[SchemeRegistration]
    dispatches: seq[DispatchSlot]
    handlerConnected: bool
    handlerRegistered: bool

  DispatchSlot = ref object
    fn: DispatchProc

  DispatchPayload = object
    state: pointer
    slot: int

  TerminatePayload = object
    shared: ptr SharedState

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

  NativeCall = object
    name: string
    id: string
    args: string

  HeaderCollector = object
    headers: seq[Header]

var liveStates {.global.}: seq[LinuxState]
var registeredSchemes {.global.}: seq[string]

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

proc initSharedBytes(value: string): SharedBytes =
  result.len = value.len
  result.data = cast[ptr UncheckedArray[char]](allocShared0(value.len + 1))
  if result.data == nil:
    raise newException(LinuxBackendError, "gtk handoff allocation failed")
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
    raise newException(LinuxBackendError, "gtk handoff allocation failed")
  try:
    result.shared = shared
    result.kind = kind
    result.ok = ok
    result.a = initSharedBytes(a)
    result.b = initSharedBytes(b)
  except CatchableError:
    freePayload(result)
    raise

proc jsCall(expr: string): string =
  "(function(){try{" & expr & "}catch(e){setTimeout(function(){throw e;},0);}})();"

proc resolveScript(id: string; ok: bool; jsonResult: string): string =
  jsCall("if(window.__viewy&&window.__viewy._resolve)window.__viewy._resolve(" &
      id.toJson() & "," & (if ok: "true" else: "false") & "," &
      jsonResult.toJson() & ");")

proc bindScript(name: string): string =
  jsCall("""
var w=window,v=w.__viewy||(w.__viewy={}),p=v._p||(v._p={}),s=Array.prototype.slice;
v._seq=v._seq||0;
v._id=v._id||function(){
  var c=w.crypto||w.msCrypto,b,i,a=[];
  if(c&&c.getRandomValues){
    b=new Uint8Array(16);
    c.getRandomValues(b);
    for(i=0;i<b.length;i++)a.push(("0"+b[i].toString(16)).slice(-2));
    return a.join("");
  }
  return String(Date.now())+"-"+String(Math.random()).slice(2)+"-"+String(++v._seq);
};
v._resolve=v._resolve||function(id,ok,json){
  var q=p[id],value;
  if(!q)return;
  delete p[id];
  try{value=json===""?undefined:JSON.parse(json);}catch(e){ok=false;value=e;}
  (ok?q.resolve:q.reject)(value);
};
if(Object.hasOwn?Object.hasOwn(w,$1):Object.prototype.hasOwnProperty.call(w,$1))throw new Error("Property "+$1+" already exists");
w[$1]=function(){
  var args=s.call(arguments),id=v._id();
  return new Promise(function(resolve,reject){
    p[id]={resolve:resolve,reject:reject};
    w.webkit.messageHandlers.$2.postMessage(JSON.stringify({name:$1,id:id,args:JSON.stringify(args)}));
  });
};
""" % [name.toJson(), nativeHandlerName])

proc rootState(state: LinuxState) =
  liveStates.add state

proc unrootState(state: LinuxState) =
  for i in 0 ..< liveStates.len:
    if liveStates[i] == state:
      liveStates.delete i
      return

proc removeBinding(state: LinuxState; name: string) =
  for i in 0 ..< state.bindings.len:
    if state.bindings[i].name == name:
      state.bindings.delete i
      return

proc findBinding(state: LinuxState; name: string): Binding =
  for binding in state.bindings:
    if binding.name == name:
      return binding

proc findScheme(state: LinuxState; scheme: string): SchemeRegistration =
  for registration in state.schemes:
    if registration.scheme == scheme:
      return registration

proc findLiveScheme(scheme: string): SchemeRegistration =
  if liveStates.len == 0:
    return nil
  for i in countdown(liveStates.high, 0):
    result = liveStates[i].findScheme(scheme)
    if result != nil:
      return

proc isSchemeRegistered(scheme: string): bool =
  for registered in registeredSchemes:
    if registered == scheme:
      return true

proc isLiveSchemeRegistered(scheme: string): bool =
  for state in liveStates:
    if state.findScheme(scheme) != nil:
      return true

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

  if state.handlerRegistered and manager != nil:
    webkitUserContentManagerUnregisterScriptMessageHandler(manager,
        nativeHandlerName)
    state.handlerRegistered = false
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

proc handoffCb(data: pointer): GBoolean {.cdecl, gcsafe.} =
  var payload = cast[ptr HandoffPayload](data)
  if payload == nil:
    return gFalse

  try:
    let shared = payload.shared
    let kind = payload.kind
    let ok = payload.ok
    let a = payload.a.toString()
    let b = payload.b.toString()
    freePayload(payload)
    payload = nil

    var webview: ptr WebKitWebView
    acquire(shared.lock)
    if not shared.closed:
      webview = shared.webview
    release(shared.lock)

    if webview != nil:
      case kind
      of hkEval:
        webkitWebViewEvaluateJavascript(webview, a.cstring, int64(a.len), nil,
            nil, nil, nil, nil)
      of hkResolve:
        let script = resolveScript(a, ok, b)
        webkitWebViewEvaluateJavascript(webview, script.cstring, int64(
            script.len), nil, nil, nil, nil, nil)
  except CatchableError:
    freePayload(payload)

  gFalse

proc dispatchPayload(shared: ptr SharedState; payload: ptr HandoffPayload) =
  if gIdleAdd(handoffCb, payload) == 0:
    freePayload(payload)
    raise newException(LinuxBackendError, "g_idle_add failed")

proc evalCurrent(state: LinuxState; js: string) =
  state.requireOpen("webkit_web_view_evaluate_javascript")
  webkitWebViewEvaluateJavascript(state.shared.webview, js.cstring, int64(
      js.len), nil, nil, nil, nil, nil)

proc messageToString(jsResult: ptr WebKitJavascriptResult): string =
  if jsResult == nil:
    return ""
  let value = webkitJavascriptResultGetJsValue(jsResult)
  if value == nil:
    return ""
  let cstr = jscValueToString(value)
  if cstr == nil:
    return ""
  result = $cstr
  gFree(cstr)

proc scriptMessageCb(manager: ptr WebKitUserContentManager;
    jsResult: ptr WebKitJavascriptResult; data: pointer) {.cdecl, gcsafe.} =
  discard manager
  let state = cast[LinuxState](data)
  try:
    let message = messageToString(jsResult)
    if message.len == 0:
      return
    let call = message.fromJson(NativeCall)
    let binding = block:
      {.cast(gcsafe).}:
        state.findBinding(call.name)
    if binding != nil:
      binding.cb(call.id, call.args)
  except CatchableError:
    discard

proc cstringToString(value: cstring): string =
  if value == nil: "" else: $value

proc cstringToString(value: GConstCharPtr): string =
  cast[cstring](value).cstringToString

proc uriPathAndQuery(request: ptr WebKitURISchemeRequest): tuple[path,
    query: string] =
  let requestUri = webkitUriSchemeRequestGetUri(request).cstringToString
  if requestUri.len > 0:
    let parsed = parseUri(requestUri)
    result.path = parsed.path
    result.query = parsed.query
  if result.path.len == 0:
    result.path = webkitUriSchemeRequestGetPath(request).cstringToString
  if result.path.len == 0:
    result.path = "/"

proc collectHeaderCb(name, value: GConstCharPtr; userData: pointer) {.cdecl,
    gcsafe.} =
  let collector = cast[ptr HeaderCollector](userData)
  if collector == nil:
    return
  {.cast(gcsafe).}:
    collector.headers.add Header((
      name: name.cstringToString,
      value: value.cstringToString,
    ))

proc requestHeaders(request: ptr WebKitURISchemeRequest): seq[Header] =
  let headers = webkitUriSchemeRequestGetHttpHeaders(request)
  if headers == nil:
    return @[]
  var collector = HeaderCollector(headers: @[])
  soupMessageHeadersForeach(headers, collectHeaderCb, addr collector)
  collector.headers

proc headerValue(headers: openArray[Header]; name: string): string =
  for header in headers:
    if cmpIgnoreCase(header.name, name) == 0:
      return header.value

proc hasHeader(headers: openArray[Header]; name: string): bool =
  headers.headerValue(name).len > 0

proc contentLength(headers: openArray[Header]): int =
  let value = headers.headerValue("Content-Length")
  if value.len == 0:
    return 0
  try:
    max(0, parseInt(value))
  except ValueError:
    0

proc requestBody(request: ptr WebKitURISchemeRequest; byteLimit: int): string =
  let stream = webkitUriSchemeRequestGetHttpBody(request)
  if stream == nil:
    return ""

  var error: ptr GError
  var buffer: array[4096, char]
  var remaining =
    if byteLimit > 0:
      min(byteLimit, maxSchemeRequestBodyBytes)
    else:
      maxSchemeRequestBodyBytes
  while remaining > 0:
    let chunk = min(buffer.len, remaining)
    let count = gInputStreamRead(stream, addr buffer[0], chunk.GSize, nil,
        addr error)
    if count < 0:
      if error != nil:
        gErrorFree(error)
      gObjectUnref(stream)
      raise newException(LinuxBackendError,
          "webkit_uri_scheme_request_get_http_body read failed")
    if count == 0:
      break
    let oldLen = result.len
    result.setLen(oldLen + count.int)
    copyMem(addr result[oldLen], addr buffer[0], count.int)
    remaining.dec count.int
  if byteLimit <= 0 and remaining == 0:
    gObjectUnref(stream)
    raise newException(LinuxBackendError,
        "webkit_uri_scheme_request_get_http_body exceeded maximum size")
  gObjectUnref(stream)

proc schemeTextResponse(status: int; statusText, body: string): AssetResponse =
  AssetResponse(
    status: status,
    statusText: statusText,
    mimeType: "text/plain; charset=utf-8",
    headers: @[(name: "Cache-Control", value: "no-store")],
    body: body,
  )

proc withoutHeader(headers: openArray[Header]; name: string): seq[Header] =
  for header in headers:
    if cmpIgnoreCase(header.name, name) != 0:
      result.add header

proc normalizeSchemeResponse(response: AssetResponse): AssetResponse =
  result = response
  if cmpIgnoreCase(response.headers.headerValue("Content-Encoding"),
      "gzip") != 0:
    return
  try:
    result.body = uncompress(response.body)
    result.headers = response.headers.withoutHeader("Content-Encoding")
    result.headers = result.headers.withoutHeader("Content-Length")
  except CatchableError:
    discard

proc finishSchemeResponse(request: ptr WebKitURISchemeRequest;
    response: AssetResponse) =
  let normalized = response.normalizeSchemeResponse
  let body = normalized.body
  let bodyPtr =
    if body.len == 0:
      nil
    else:
      cast[pointer](unsafeAddr body[0])
  let bytes = gBytesNew(bodyPtr, body.len.GSize)
  let stream = gMemoryInputStreamNewFromBytes(bytes)
  gBytesUnref(bytes)

  let webResponse = webkitUriSchemeResponseNew(stream, int64(body.len))
  let status = if normalized.status >= 100: normalized.status else: 500
  let reason =
    if normalized.statusText.len > 0:
      normalized.statusText
    elif status == 500:
      "Internal Server Error"
    else:
      "OK"
  webkitUriSchemeResponseSetStatus(webResponse, cuint(status), reason.cstring)
  if normalized.mimeType.len > 0:
    webkitUriSchemeResponseSetContentType(webResponse,
        normalized.mimeType.cstring)

  let headers = soupMessageHeadersNew(soupMessageHeadersResponse)
  if headers != nil:
    for header in normalized.headers:
      if header.name.len > 0 and header.value.len > 0:
        soupMessageHeadersAppend(headers, header.name.cstring,
            header.value.cstring)
    if normalized.mimeType.len > 0 and not normalized.headers.hasHeader(
        "Content-Type"):
      soupMessageHeadersAppend(headers, "Content-Type",
          normalized.mimeType.cstring)
    webkitUriSchemeResponseSetHttpHeaders(webResponse, headers)

  webkitUriSchemeRequestFinishWithResponse(request, webResponse)
  if stream != nil:
    gObjectUnref(stream)
  if webResponse != nil:
    gObjectUnref(webResponse)

proc schemeRequestCb(request: ptr WebKitURISchemeRequest;
    data: pointer) {.cdecl, gcsafe.} =
  discard data

  try:
    let scheme = webkitUriSchemeRequestGetScheme(request).cstringToString
    let registration = block:
      {.cast(gcsafe).}:
        findLiveScheme(scheme)
    if registration == nil:
      finishSchemeResponse(request, schemeTextResponse(404, "Not Found",
        "not found"))
      return

    let route = uriPathAndQuery(request)
    var httpMethod = webkitUriSchemeRequestGetHttpMethod(
        request).cstringToString
    if httpMethod.len == 0:
      httpMethod = "GET"
    else:
      httpMethod = httpMethod.toUpperAscii
    let headers = request.requestHeaders
    let body =
      if httpMethod in ["GET", "HEAD"]: "" else: request.requestBody(
          headers.contentLength)
    let assetRequest = AssetRequest(
      scheme: scheme,
      httpMethod: httpMethod,
      path: route.path,
      query: route.query,
      headers: headers,
      body: body,
    )
    let response = block:
      {.cast(gcsafe).}:
        registration.handler(assetRequest)
    finishSchemeResponse(request, response)
  except CatchableError:
    finishSchemeResponse(request, schemeTextResponse(500,
      "Internal Server Error", "internal server error"))

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
    bindings: @[],
    schemes: @[],
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
  let shared = h.toShared
  acquire(shared.lock)
  try:
    shared.requireOpen("g_idle_add")
    dispatchPayload(shared, newPayload(shared, hkEval, js))
  finally:
    release(shared.lock)

proc dispatchResolve(h: BackendHandle; id: string; ok: bool;
    jsonResult: string) {.gcsafe.} =
  let shared = h.toShared
  acquire(shared.lock)
  try:
    shared.requireOpen("g_idle_add")
    dispatchPayload(shared, newPayload(shared, hkResolve, id, jsonResult, ok))
  finally:
    release(shared.lock)

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

proc addUserScript(state: LinuxState; js: string) =
  state.assertUiThread
  state.requireOpen("webkit_user_content_manager_add_script")
  let script = webkitUserScriptNew(js.cstring, webkitUserContentInjectTopFrame,
      webkitUserScriptInjectAtDocumentStart, nil, nil)
  if script == nil:
    raise newException(LinuxBackendError, "webkit_user_script_new failed")
  webkitUserContentManagerAddScript(state.shared.manager, script)
  webkitUserScriptUnref(script)

proc init(h: BackendHandle; js: string) =
  h.toState.addUserScript(js)

proc bindFn(h: BackendHandle; name: string; cb: BindCallback) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("webkit_user_content_manager_register_script_message_handler")
  if state.findBinding(name) != nil:
    raise newException(LinuxBackendError,
        "native Linux bind failed: duplicate binding " & name)

  if not state.handlerConnected:
    discard gSignalConnectData(state.shared.manager,
        "script-message-received::" & nativeHandlerName, cast[pointer](
        scriptMessageCb),
        cast[pointer](state), nil, gConnectDefault)
    state.handlerConnected = true

  if not state.handlerRegistered:
    if webkitUserContentManagerRegisterScriptMessageHandler(
        state.shared.manager, nativeHandlerName) == gFalse:
      raise newException(LinuxBackendError,
          "webkit_user_content_manager_register_script_message_handler failed")
    state.handlerRegistered = true

  let binding = Binding(name: name, cb: cb)
  state.bindings.add binding
  let script = bindScript(name)
  state.addUserScript(script)
  state.evalCurrent(script)

proc unbind(h: BackendHandle; name: string) =
  let state = h.toState
  state.assertUiThread
  state.removeBinding(name)
  let script = jsCall("delete window[" & name.toJson() & "];")
  state.addUserScript(script)
  state.evalCurrent(script)

proc resolve(h: BackendHandle; id: string; ok: bool; jsonResult: string) =
  let state = h.toState
  state.assertUiThread
  state.evalCurrent(resolveScript(id, ok, jsonResult))

proc registerScheme(h: BackendHandle; scheme: string; handler: AssetHandler) =
  let state = h.toState
  state.assertUiThread
  state.requireOpen("webkit_web_context_register_uri_scheme")
  if scheme.len == 0:
    raise newException(LinuxBackendError,
        "native Linux scheme registration failed: empty scheme")
  if handler.isNil:
    raise newException(LinuxBackendError,
        "native Linux scheme registration failed: nil handler")
  if isLiveSchemeRegistered(scheme):
    raise newException(LinuxBackendError,
        "native Linux scheme registration failed: duplicate scheme " & scheme)

  let context = webkitWebContextGetDefault()
  if context == nil:
    raise newException(LinuxBackendError, "webkit_web_context_get_default failed")
  state.schemes.add SchemeRegistration(scheme: scheme, handler: handler)
  if not isSchemeRegistered(scheme):
    webkitWebContextRegisterUriScheme(context, scheme.cstring, schemeRequestCb,
        nil, nil)
    registeredSchemes.add scheme

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
    caps: {capScheme},
    registerSchemeImpl: registerScheme,
  )
