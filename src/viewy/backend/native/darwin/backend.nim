## Native macOS backend backed by Cocoa and WKWebView through thin Obj-C glue.

import std/[locks, os, strutils]

import ../../api

import jsony
import zippy

export api

when defined(macosx):
  const gluePath = "glue.m"
  {.passC: "-I" & currentSourcePath().parentDir.}
  {.passL: "-framework Cocoa -framework WebKit".}
  {.compile(gluePath, "-fobjc-arc").}

type
  DarwinBackendError* = object of CatchableError

  ConstCString {.importc: "const char *", nodecl.} = distinct cstring
  ConstUint8Ptr {.importc: "const uint8_t *", nodecl.} = distinct pointer
  ViewyDarwinApp {.importc: "ViewyDarwinApp", header: "glue.h",
      incompleteStruct.} = object
  ViewyDarwinWindow {.importc: "ViewyDarwinWindow", header: "glue.h",
      incompleteStruct.} = object

  DarwinMessageCallback = proc(userdata: pointer; name, id,
      jsonArgs: ConstCString) {.cdecl, gcsafe.}
  DarwinEventCallback = proc(userdata: pointer; kind, width,
      height: int32) {.cdecl, gcsafe.}
  DarwinDispatchCallback = proc(userdata: pointer) {.cdecl, gcsafe.}
  DarwinSchemeCallback = proc(userdata, request: pointer; scheme, httpMethod,
      path, query, headersJson: ConstCString; body: ConstUint8Ptr;
      bodyLen: int64) {.cdecl, gcsafe.}

  SharedState = object
    lock: Lock
    mainThreadId: int
    closed: bool
    app: ptr ViewyDarwinApp
    window: ptr ViewyDarwinWindow
    owner: pointer

  DarwinState = ref object
    shared: ptr SharedState
    bindings: seq[Binding]
    schemes: seq[SchemeRegistration]
    dispatches: seq[DispatchSlot]
    handlerRegistered: bool
    eventCallback: WindowEventCallback

  Binding = ref object
    name: string
    cb: BindCallback

  SchemeRegistration = ref object
    scheme: string
    handler: AssetHandler

  HeaderJson = object
    name: string
    value: string

  DispatchSlot = ref object
    fn: DispatchProc

  DispatchPayload = object
    state: pointer
    slot: int

  HandoffKind = enum
    hkEval
    hkResolve
    hkTerminate

  SharedBytes = object
    len: int
    data: ptr UncheckedArray[char]

  HandoffPayload = object
    state: pointer
    kind: HandoffKind
    ok: bool
    a: SharedBytes
    b: SharedBytes

proc viewyDarwinAppCreate(): ptr ViewyDarwinApp {.
    importc: "viewy_darwin_app_create", header: "glue.h".}
proc viewyDarwinAppDestroy(app: ptr ViewyDarwinApp) {.
    importc: "viewy_darwin_app_destroy", header: "glue.h".}
proc viewyDarwinAppRun(app: ptr ViewyDarwinApp) {.
    importc: "viewy_darwin_app_run", header: "glue.h".}
proc viewyDarwinAppStop(app: ptr ViewyDarwinApp) {.
    importc: "viewy_darwin_app_stop", header: "glue.h".}
proc viewyDarwinAppDispatch(app: ptr ViewyDarwinApp;
    fn: DarwinDispatchCallback; userdata: pointer) {.
    importc: "viewy_darwin_app_dispatch", header: "glue.h".}
proc viewyDarwinWindowCreate(app: ptr ViewyDarwinApp;
    debug: int32): ptr ViewyDarwinWindow {.
    importc: "viewy_darwin_window_create", header: "glue.h".}
proc viewyDarwinWindowDestroy(window: ptr ViewyDarwinWindow) {.
    importc: "viewy_darwin_window_destroy", header: "glue.h".}
proc viewyDarwinWindowSetTitle(window: ptr ViewyDarwinWindow; title: cstring) {.
    importc: "viewy_darwin_window_set_title", header: "glue.h".}
proc viewyDarwinWindowSetSize(window: ptr ViewyDarwinWindow; width, height,
    hints: int32) {.importc: "viewy_darwin_window_set_size", header: "glue.h".}
proc viewyDarwinWindowSetHtml(window: ptr ViewyDarwinWindow; html: cstring) {.
    importc: "viewy_darwin_window_set_html", header: "glue.h".}
proc viewyDarwinWindowNavigate(window: ptr ViewyDarwinWindow; url: cstring) {.
    importc: "viewy_darwin_window_navigate", header: "glue.h".}
proc viewyDarwinWindowEval(window: ptr ViewyDarwinWindow; js: cstring) {.
    importc: "viewy_darwin_window_eval", header: "glue.h".}
proc viewyDarwinWindowInitScript(window: ptr ViewyDarwinWindow; js: cstring) {.
    importc: "viewy_darwin_window_init_script", header: "glue.h".}
proc viewyDarwinSetMessageHandler(window: ptr ViewyDarwinWindow;
    handlerName: cstring; callback: DarwinMessageCallback;
    userdata: pointer): int32 {.
    importc: "viewy_darwin_set_message_handler", header: "glue.h".}
proc viewyDarwinClearMessageHandler(window: ptr ViewyDarwinWindow;
    handlerName: cstring) {.
    importc: "viewy_darwin_clear_message_handler", header: "glue.h".}
proc viewyDarwinResolve(window: ptr ViewyDarwinWindow; id: cstring;
    ok: int32; jsonResult: cstring) {.
    importc: "viewy_darwin_resolve", header: "glue.h".}
proc viewyDarwinSetEventCallback(window: ptr ViewyDarwinWindow;
    callback: DarwinEventCallback; userdata: pointer) {.
    importc: "viewy_darwin_set_event_callback", header: "glue.h".}
proc viewyDarwinRegisterScheme(window: ptr ViewyDarwinWindow; scheme: cstring;
    callback: DarwinSchemeCallback; userdata: pointer): int32 {.
    importc: "viewy_darwin_register_scheme", header: "glue.h".}
proc viewyDarwinSchemeFinish(request: pointer; status: int32; statusText,
    mimeType, headersJson: cstring; body: pointer; bodyLen: int64) {.
    importc: "viewy_darwin_scheme_finish", header: "glue.h".}

const nativeHandlerName = "viewy"

proc cstringToString(value: ConstCString): string =
  let raw = cast[cstring](value)
  if raw == nil: "" else: $raw

proc toHandle(state: DarwinState): BackendHandle =
  cast[BackendHandle](state.shared)

proc toShared(h: BackendHandle): ptr SharedState =
  doAssert h != nil, "viewy backend handle is nil"
  result = cast[ptr SharedState](h)

proc requireOpen(shared: ptr SharedState; op: string) =
  if shared.closed or shared.window == nil or shared.app == nil:
    raise newException(DarwinBackendError, op & " failed: backend is closed")

proc toState(h: BackendHandle): DarwinState =
  let shared = h.toShared
  shared.requireOpen("darwin backend operation")
  result = cast[DarwinState](shared.owner)
  if result == nil:
    raise newException(DarwinBackendError, "darwin backend operation failed: backend is closed")

proc assertUiThread(state: DarwinState) =
  when not defined(release):
    doAssert getThreadId() == state.shared.mainThreadId,
        "viewy backend operation must run on the UI thread"

proc initSharedBytes(value: string): SharedBytes =
  result.len = value.len
  result.data = cast[ptr UncheckedArray[char]](allocShared0(value.len + 1))
  if result.data == nil:
    raise newException(DarwinBackendError, "darwin handoff allocation failed")
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

proc bodyToString(body: pointer; bodyLen: int64): string =
  if body == nil or bodyLen <= 0:
    return ""
  result = newString(bodyLen.int)
  copyMem(addr result[0], body, bodyLen.int)

proc headerItems(headers: openArray[Header]): seq[HeaderJson] =
  for header in headers:
    result.add HeaderJson(name: header.name, value: header.value)

proc headersFromJson(headersJson: string): seq[Header] =
  try:
    for item in headersJson.fromJson(seq[HeaderJson]):
      result.add Header((name: item.name, value: item.value))
  except CatchableError:
    result = @[]

proc newPayload(shared: ptr SharedState; kind: HandoffKind; a = ""; b = "";
    ok = false): ptr HandoffPayload =
  result = cast[ptr HandoffPayload](allocShared0(sizeof(HandoffPayload)))
  if result == nil:
    raise newException(DarwinBackendError, "darwin handoff allocation failed")
  try:
    result.state = cast[pointer](shared)
    result.kind = kind
    result.ok = ok
    result.a = initSharedBytes(a)
    result.b = initSharedBytes(b)
  except CatchableError:
    freePayload(result)
    raise

proc findBinding(state: DarwinState; name: string): Binding =
  for binding in state.bindings:
    if binding.name == name:
      return binding

proc findScheme(state: DarwinState; scheme: string): SchemeRegistration =
  for registration in state.schemes:
    if registration.scheme == scheme:
      return registration

proc hasScheme(state: DarwinState; scheme: string): bool =
  state.findScheme(scheme) != nil

proc headerValue(headers: openArray[Header]; name: string): string =
  for header in headers:
    if cmpIgnoreCase(header.name, name) == 0:
      return header.value

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

proc schemeTextResponse(status: int; statusText, body: string): AssetResponse =
  AssetResponse(
    status: status,
    statusText: statusText,
    mimeType: "text/plain; charset=utf-8",
    headers: @[(name: "Cache-Control", value: "no-store")],
    body: body,
  )

proc removeBinding(state: DarwinState; name: string) =
  for i in 0 ..< state.bindings.len:
    if state.bindings[i].name == name:
      state.bindings.delete i
      return

proc jsCall(expr: string): string =
  "(function(){try{" & expr & "}catch(e){setTimeout(function(){throw e;},0);}})();"

proc bindScript(name: string): string =
  jsCall("""
	var w=window,v=w.__viewy||(w.__viewy={}),p=v._p||(v._p={}),b=v._b||(v._b={}),s=Array.prototype.slice;
	v._seq=v._seq||0;
	v._id=v._id||function(){return String(Date.now())+"-"+String(Math.random()).slice(2)+"-"+String(++v._seq);};
	v._resolve=v._resolve||function(id,ok,json){
  var q=p[id],value;
  if(!q)return;
  delete p[id];
	  try{value=json===""?undefined:JSON.parse(json);}catch(e){ok=false;value=e;}
	  (ok?q.resolve:q.reject)(value);
	};
	if((Object.hasOwn?Object.hasOwn(w,$1):Object.prototype.hasOwnProperty.call(w,$1))&&!b[$1])throw new Error("Property "+$1+" already exists");
	b[$1]=true;
	w[$1]=function(){
	  var args=s.call(arguments),id=v._id();
	  return new Promise(function(resolve,reject){
    p[id]={resolve:resolve,reject:reject};
    w.webkit.messageHandlers.$2.postMessage({name:$1,id:id,args:JSON.stringify(args)});
  });
};
""" % [name.toJson(), nativeHandlerName])

proc messageCb(userdata: pointer; name, id,
    jsonArgs: ConstCString) {.cdecl, gcsafe.} =
  let state = cast[DarwinState](userdata)
  if state == nil or state.shared == nil or state.shared.closed:
    return
  let binding = state.findBinding(name.cstringToString)
  if binding != nil:
    binding.cb(id.cstringToString, jsonArgs.cstringToString)

proc schemeCb(userdata, request: pointer; scheme, httpMethod, path, query,
    headersJson: ConstCString; body: ConstUint8Ptr; bodyLen: int64) {.cdecl,
    gcsafe.} =
  let state = cast[DarwinState](userdata)
  try:
    if state == nil or state.shared == nil or state.shared.closed:
      let response = schemeTextResponse(404, "Not Found", "not found")
      let headers = response.headers.headerItems.toJson()
      viewyDarwinSchemeFinish(request, response.status.int32,
        response.statusText.cstring, response.mimeType.cstring, headers.cstring,
        cast[pointer](unsafeAddr response.body[0]), response.body.len.int64)
      return

    let schemeName = scheme.cstringToString
    let registration = state.findScheme(schemeName)
    if registration == nil:
      let response = schemeTextResponse(404, "Not Found", "not found")
      let headers = response.headers.headerItems.toJson()
      viewyDarwinSchemeFinish(request, response.status.int32,
        response.statusText.cstring, response.mimeType.cstring, headers.cstring,
        cast[pointer](unsafeAddr response.body[0]), response.body.len.int64)
      return

    var httpVerb = httpMethod.cstringToString.toUpperAscii
    if httpVerb.len == 0:
      httpVerb = "GET"
    let bodyString =
      if httpVerb in ["GET", "HEAD"]:
        ""
      else:
        cast[pointer](body).bodyToString(bodyLen)
    let assetRequest = AssetRequest(
      scheme: schemeName,
      httpMethod: httpVerb,
      path: path.cstringToString,
      query: query.cstringToString,
      headers: headersJson.cstringToString.headersFromJson,
      body: bodyString,
    )
    let response = registration.handler(assetRequest).normalizeSchemeResponse
    let headers = response.headers.headerItems.toJson()
    let bodyPtr =
      if response.body.len == 0:
        nil
      else:
        cast[pointer](unsafeAddr response.body[0])
    viewyDarwinSchemeFinish(request, response.status.int32,
      response.statusText.cstring, response.mimeType.cstring, headers.cstring,
      bodyPtr, response.body.len.int64)
  except CatchableError:
    let response = schemeTextResponse(500, "Internal Server Error",
      "internal server error")
    let headers = response.headers.headerItems.toJson()
    viewyDarwinSchemeFinish(request, response.status.int32,
      response.statusText.cstring, response.mimeType.cstring, headers.cstring,
      cast[pointer](unsafeAddr response.body[0]), response.body.len.int64)

proc eventCb(userdata: pointer; kind, width, height: int32) {.cdecl, gcsafe.} =
  let state = cast[DarwinState](userdata)
  if state == nil or state.shared == nil or state.shared.closed:
    return
  if kind == 0 and state.shared.app != nil:
    viewyDarwinAppStop(state.shared.app)
  if state.eventCallback.isNil:
    return
  let eventKind =
    case kind
    of 0: weClose
    of 1: weFocus
    of 2: weBlur
    else: weResize
  state.eventCallback(WindowEvent(kind: eventKind, width: width,
      height: height))

proc dispatchCb(userdata: pointer) {.cdecl, gcsafe.} =
  let payload = cast[ptr DispatchPayload](userdata)
  if payload == nil:
    return
  let state = cast[DarwinState](payload.state)
  let slot = payload.slot
  deallocShared(payload)
  if state == nil:
    return
  try:
    if not state.shared.closed and slot >= 0 and slot < state.dispatches.len:
      let dispatch = state.dispatches[slot]
      state.dispatches[slot] = nil
      if dispatch != nil:
        dispatch.fn()
  finally:
    GC_unref(state)

proc handoffCb(userdata: pointer) {.cdecl, gcsafe.} =
  var payload = cast[ptr HandoffPayload](userdata)
  if payload == nil:
    return
  try:
    let shared = cast[ptr SharedState](payload.state)
    if shared == nil or shared.closed or shared.window == nil or shared.app == nil:
      freePayload(payload)
      return
    let a = payload.a.toString()
    let b = payload.b.toString()
    let ok = payload.ok
    let kind = payload.kind
    freePayload(payload)
    payload = nil
    case kind
    of hkEval:
      viewyDarwinWindowEval(shared.window, a.cstring)
    of hkResolve:
      viewyDarwinResolve(shared.window, a.cstring, (if ok: 1'i32 else: 0'i32),
          b.cstring)
    of hkTerminate:
      viewyDarwinAppStop(shared.app)
  except CatchableError:
    freePayload(payload)

proc create(debug: bool): BackendHandle =
  let shared = cast[ptr SharedState](allocShared0(sizeof(SharedState)))
  if shared == nil:
    raise newException(DarwinBackendError, "darwin backend create failed: out of memory")
  shared.mainThreadId = getThreadId()
  initLock(shared.lock)
  shared.app = viewyDarwinAppCreate()
  if shared.app == nil:
    deinitLock(shared.lock)
    deallocShared(shared)
    raise newException(DarwinBackendError, "viewy_darwin_app_create failed")
  shared.window = viewyDarwinWindowCreate(shared.app, if debug: 1'i32 else: 0'i32)
  if shared.window == nil:
    viewyDarwinAppDestroy(shared.app)
    deinitLock(shared.lock)
    deallocShared(shared)
    raise newException(DarwinBackendError, "viewy_darwin_window_create failed")
  let state = DarwinState(shared: shared, bindings: @[], schemes: @[],
      dispatches: @[])
  shared.owner = cast[pointer](state)
  viewyDarwinSetEventCallback(shared.window, eventCb, cast[pointer](state))
  GC_ref(state)
  state.toHandle

proc destroy(h: BackendHandle) =
  let shared = cast[ptr SharedState](h)
  if shared == nil:
    return
  let state = cast[DarwinState](shared.owner)
  if state == nil:
    return
  state.assertUiThread
  acquire(shared.lock)
  if not shared.closed:
    shared.closed = true
  release(shared.lock)
  if shared.window != nil:
    if state.handlerRegistered and shared.window != nil:
      viewyDarwinClearMessageHandler(shared.window, nativeHandlerName)
    viewyDarwinSetEventCallback(shared.window, nil, nil)
    viewyDarwinWindowDestroy(shared.window)
    shared.window = nil
  if shared.app != nil:
    viewyDarwinAppDestroy(shared.app)
    shared.app = nil
  state.bindings.setLen(0)
  state.schemes.setLen(0)
  state.dispatches.setLen(0)
  state.eventCallback = nil
  shared.owner = nil
  GC_unref(state)
  # SharedState intentionally remains allocated after destroy. BackendHandle is an
  # unmanaged pointer that worker threads may still hold; keeping closed state
  # readable lets late typed handoffs fail before touching native handles.

proc run(h: BackendHandle) =
  let state = h.toState
  state.assertUiThread
  viewyDarwinAppRun(state.shared.app)

proc terminate(h: BackendHandle) {.gcsafe.} =
  let shared = cast[ptr SharedState](h)
  if shared == nil:
    return
  viewyDarwinAppStop(shared.app)

proc dispatch(h: BackendHandle; fn: DispatchProc) {.gcsafe.} =
  let state = block:
    {.cast(gcsafe).}:
      h.toState
  if fn.isNil:
    return
  if getThreadId() != state.shared.mainThreadId:
    raise newException(DarwinBackendError,
        "darwin dispatch failed: closure dispatch is UI-thread only; use typed handoff")
  let payload = cast[ptr DispatchPayload](allocShared0(sizeof(DispatchPayload)))
  if payload == nil:
    raise newException(DarwinBackendError, "darwin dispatch allocation failed")
  let slot = state.dispatches.len
  state.dispatches.add DispatchSlot(fn: fn)
  payload.state = cast[pointer](state)
  payload.slot = slot
  GC_ref(state)
  viewyDarwinAppDispatch(state.shared.app, dispatchCb, payload)

proc dispatchEval(h: BackendHandle; js: string) {.gcsafe.} =
  let shared = h.toShared
  acquire(shared.lock)
  try:
    shared.requireOpen("darwin dispatch")
    viewyDarwinAppDispatch(shared.app, handoffCb, newPayload(shared, hkEval, js))
  finally:
    release(shared.lock)

proc dispatchResolve(h: BackendHandle; id: string; ok: bool;
    jsonResult: string) {.gcsafe.} =
  let shared = h.toShared
  acquire(shared.lock)
  try:
    shared.requireOpen("darwin dispatch")
    viewyDarwinAppDispatch(shared.app, handoffCb, newPayload(shared, hkResolve, id,
        jsonResult, ok))
  finally:
    release(shared.lock)

proc dispatchTerminate(h: BackendHandle) {.gcsafe.} =
  let shared = h.toShared
  acquire(shared.lock)
  try:
    shared.requireOpen("darwin dispatch")
    viewyDarwinAppDispatch(shared.app, handoffCb, newPayload(shared, hkTerminate))
  finally:
    release(shared.lock)

proc setTitle(h: BackendHandle; title: string) =
  viewyDarwinWindowSetTitle(h.toState.shared.window, title.cstring)

proc setSize(h: BackendHandle; width, height: int; hints: WindowHints) =
  viewyDarwinWindowSetSize(h.toState.shared.window, width.int32, height.int32,
      ord(hints).int32)

proc navigate(h: BackendHandle; url: string) =
  viewyDarwinWindowNavigate(h.toState.shared.window, url.cstring)

proc setHtml(h: BackendHandle; html: string) =
  viewyDarwinWindowSetHtml(h.toState.shared.window, html.cstring)

proc eval(h: BackendHandle; js: string) =
  viewyDarwinWindowEval(h.toState.shared.window, js.cstring)

proc init(h: BackendHandle; js: string) =
  viewyDarwinWindowInitScript(h.toState.shared.window, js.cstring)

proc bindFn(h: BackendHandle; name: string; cb: BindCallback) =
  let state = h.toState
  state.assertUiThread
  if state.findBinding(name) != nil:
    raise newException(DarwinBackendError,
        "native macOS bind failed: duplicate binding " & name)
  if not state.handlerRegistered:
    if viewyDarwinSetMessageHandler(state.shared.window, nativeHandlerName, messageCb,
        cast[pointer](state)) == 0:
      raise newException(DarwinBackendError,
          "viewy_darwin_set_message_handler failed")
  state.handlerRegistered = true
  state.bindings.add Binding(name: name, cb: cb)
  let script = bindScript(name)
  viewyDarwinWindowInitScript(state.shared.window, script.cstring)
  viewyDarwinWindowEval(state.shared.window, script.cstring)

proc unbind(h: BackendHandle; name: string) =
  let state = h.toState
  state.assertUiThread
  state.removeBinding(name)
  let script = jsCall("if(window.__viewy&&window.__viewy._b)delete window.__viewy._b[" &
      name.toJson() & "];delete window[" & name.toJson() & "];")
  viewyDarwinWindowInitScript(state.shared.window, script.cstring)
  viewyDarwinWindowEval(state.shared.window, script.cstring)

proc registerScheme(h: BackendHandle; scheme: string; handler: AssetHandler) =
  let state = h.toState
  state.assertUiThread
  if scheme.len == 0:
    raise newException(DarwinBackendError,
        "native macOS scheme registration failed: empty scheme")
  if handler.isNil:
    raise newException(DarwinBackendError,
        "native macOS scheme registration failed: nil handler")
  if state.hasScheme(scheme):
    raise newException(DarwinBackendError,
        "native macOS scheme registration failed: duplicate scheme " & scheme)
  if viewyDarwinRegisterScheme(state.shared.window, scheme.cstring, schemeCb,
      cast[pointer](state)) == 0:
    raise newException(DarwinBackendError,
        "viewy_darwin_register_scheme failed")
  state.schemes.add SchemeRegistration(scheme: scheme, handler: handler)

proc resolve(h: BackendHandle; id: string; ok: bool; jsonResult: string) =
  viewyDarwinResolve(h.toState.shared.window, id.cstring, (if ok: 1'i32 else: 0'i32),
      jsonResult.cstring)

proc onWindowEvent(h: BackendHandle; cb: WindowEventCallback) =
  h.toState.eventCallback = cb

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
    caps: {capScheme, capWindowEvents},
    registerSchemeImpl: registerScheme,
    onWindowEventImpl: onWindowEvent,
  )
