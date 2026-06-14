## Native macOS backend backed by Cocoa and WKWebView through thin Obj-C glue.

import std/[locks, os, strutils]

import ../../api

import jsony

export api

when defined(macosx):
  const gluePath = "glue.m"
  {.passC: "-I" & currentSourcePath().parentDir.}
  {.passL: "-framework Cocoa -framework WebKit".}
  {.compile(gluePath, "-fobjc-arc").}

type
  DarwinBackendError* = object of CatchableError

  ConstCString {.importc: "const char *", nodecl.} = distinct cstring
  ViewyDarwinApp {.importc: "ViewyDarwinApp", header: "glue.h",
      incompleteStruct.} = object
  ViewyDarwinWindow {.importc: "ViewyDarwinWindow", header: "glue.h",
      incompleteStruct.} = object

  DarwinMessageCallback = proc(userdata: pointer; name, id,
      jsonArgs: ConstCString) {.cdecl, gcsafe.}
  DarwinEventCallback = proc(userdata: pointer; kind, width,
      height: int32) {.cdecl, gcsafe.}
  DarwinDispatchCallback = proc(userdata: pointer) {.cdecl, gcsafe.}

  DarwinState = ref object
    lock: Lock
    mainThreadId: int
    closed: bool
    app: ptr ViewyDarwinApp
    window: ptr ViewyDarwinWindow
    bindings: seq[Binding]
    dispatches: seq[DispatchSlot]
    handlerRegistered: bool
    eventCallback: WindowEventCallback

  Binding = ref object
    name: string
    cb: BindCallback

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

const nativeHandlerName = "viewy"

proc cstringToString(value: ConstCString): string =
  let raw = cast[cstring](value)
  if raw == nil: "" else: $raw

proc toHandle(state: DarwinState): BackendHandle =
  cast[BackendHandle](state)

proc toState(h: BackendHandle): DarwinState =
  doAssert h != nil, "viewy backend handle is nil"
  result = cast[DarwinState](h)
  if result.closed or result.window == nil:
    raise newException(DarwinBackendError, "viewy backend handle is closed")

proc assertUiThread(state: DarwinState) =
  when not defined(release):
    doAssert getThreadId() == state.mainThreadId,
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

proc newPayload(state: DarwinState; kind: HandoffKind; a = ""; b = "";
    ok = false): ptr HandoffPayload =
  result = cast[ptr HandoffPayload](allocShared0(sizeof(HandoffPayload)))
  if result == nil:
    raise newException(DarwinBackendError, "darwin handoff allocation failed")
  try:
    result.state = cast[pointer](state)
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

proc removeBinding(state: DarwinState; name: string) =
  for i in 0 ..< state.bindings.len:
    if state.bindings[i].name == name:
      state.bindings.delete i
      return

proc jsCall(expr: string): string =
  "(function(){try{" & expr & "}catch(e){setTimeout(function(){throw e;},0);}})();"

proc bindScript(name: string): string =
  jsCall("""
var w=window,v=w.__viewy||(w.__viewy={}),p=v._p||(v._p={}),s=Array.prototype.slice;
v._seq=v._seq||0;
v._id=v._id||function(){return String(Date.now())+"-"+String(Math.random()).slice(2)+"-"+String(++v._seq);};
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
    w.webkit.messageHandlers.$2.postMessage({name:$1,id:id,args:JSON.stringify(args)});
  });
};
""" % [name.toJson(), nativeHandlerName])

proc messageCb(userdata: pointer; name, id,
    jsonArgs: ConstCString) {.cdecl, gcsafe.} =
  let state = cast[DarwinState](userdata)
  if state == nil:
    return
  let binding = state.findBinding(name.cstringToString)
  if binding != nil:
    binding.cb(id.cstringToString, jsonArgs.cstringToString)

proc eventCb(userdata: pointer; kind, width, height: int32) {.cdecl, gcsafe.} =
  let state = cast[DarwinState](userdata)
  if state == nil or state.eventCallback.isNil:
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
  if slot >= 0 and slot < state.dispatches.len:
    let dispatch = state.dispatches[slot]
    state.dispatches[slot] = nil
    if dispatch != nil:
      dispatch.fn()

proc handoffCb(userdata: pointer) {.cdecl, gcsafe.} =
  var payload = cast[ptr HandoffPayload](userdata)
  if payload == nil:
    return
  try:
    let state = cast[DarwinState](payload.state)
    if state == nil or state.closed:
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
      viewyDarwinWindowEval(state.window, a.cstring)
    of hkResolve:
      viewyDarwinResolve(state.window, a.cstring, (if ok: 1'i32 else: 0'i32),
          b.cstring)
    of hkTerminate:
      viewyDarwinAppStop(state.app)
  except CatchableError:
    freePayload(payload)

proc create(debug: bool): BackendHandle =
  let state = DarwinState(mainThreadId: getThreadId(), bindings: @[],
      dispatches: @[])
  initLock(state.lock)
  state.app = viewyDarwinAppCreate()
  if state.app == nil:
    raise newException(DarwinBackendError, "viewy_darwin_app_create failed")
  state.window = viewyDarwinWindowCreate(state.app, if debug: 1'i32 else: 0'i32)
  if state.window == nil:
    viewyDarwinAppDestroy(state.app)
    raise newException(DarwinBackendError, "viewy_darwin_window_create failed")
  viewyDarwinSetEventCallback(state.window, eventCb, cast[pointer](state))
  GC_ref(state)
  state.toHandle

proc destroy(h: BackendHandle) =
  let state = cast[DarwinState](h)
  if state == nil:
    return
  state.assertUiThread
  if not state.closed:
    state.closed = true
    if state.handlerRegistered and state.window != nil:
      viewyDarwinClearMessageHandler(state.window, nativeHandlerName)
    if state.window != nil:
      viewyDarwinWindowDestroy(state.window)
      state.window = nil
    if state.app != nil:
      viewyDarwinAppDestroy(state.app)
      state.app = nil
  deinitLock(state.lock)
  GC_unref(state)

proc run(h: BackendHandle) =
  let state = h.toState
  state.assertUiThread
  viewyDarwinAppRun(state.app)

proc terminate(h: BackendHandle) {.gcsafe.} =
  let state = cast[DarwinState](h)
  if state == nil:
    return
  viewyDarwinAppStop(state.app)

proc dispatch(h: BackendHandle; fn: DispatchProc) {.gcsafe.} =
  let state = cast[DarwinState](h)
  if state == nil or fn.isNil:
    return
  let payload = cast[ptr DispatchPayload](allocShared0(sizeof(DispatchPayload)))
  if payload == nil:
    raise newException(DarwinBackendError, "darwin dispatch allocation failed")
  acquire(state.lock)
  let slot = state.dispatches.len
  state.dispatches.add DispatchSlot(fn: fn)
  release(state.lock)
  payload.state = cast[pointer](state)
  payload.slot = slot
  viewyDarwinAppDispatch(state.app, dispatchCb, payload)

proc dispatchEval(h: BackendHandle; js: string) {.gcsafe.} =
  let state = cast[DarwinState](h)
  if state == nil:
    return
  viewyDarwinAppDispatch(state.app, handoffCb, newPayload(state, hkEval, js))

proc dispatchResolve(h: BackendHandle; id: string; ok: bool;
    jsonResult: string) {.gcsafe.} =
  let state = cast[DarwinState](h)
  if state == nil:
    return
  viewyDarwinAppDispatch(state.app, handoffCb, newPayload(state, hkResolve, id,
      jsonResult, ok))

proc dispatchTerminate(h: BackendHandle) {.gcsafe.} =
  let state = cast[DarwinState](h)
  if state == nil:
    return
  viewyDarwinAppDispatch(state.app, handoffCb, newPayload(state, hkTerminate))

proc setTitle(h: BackendHandle; title: string) =
  viewyDarwinWindowSetTitle(h.toState.window, title.cstring)

proc setSize(h: BackendHandle; width, height: int; hints: WindowHints) =
  viewyDarwinWindowSetSize(h.toState.window, width.int32, height.int32,
      ord(hints).int32)

proc navigate(h: BackendHandle; url: string) =
  viewyDarwinWindowNavigate(h.toState.window, url.cstring)

proc setHtml(h: BackendHandle; html: string) =
  viewyDarwinWindowSetHtml(h.toState.window, html.cstring)

proc eval(h: BackendHandle; js: string) =
  viewyDarwinWindowEval(h.toState.window, js.cstring)

proc init(h: BackendHandle; js: string) =
  viewyDarwinWindowInitScript(h.toState.window, js.cstring)

proc bindFn(h: BackendHandle; name: string; cb: BindCallback) =
  let state = h.toState
  state.assertUiThread
  if state.findBinding(name) != nil:
    raise newException(DarwinBackendError,
        "native macOS bind failed: duplicate binding " & name)
  if not state.handlerRegistered:
    if viewyDarwinSetMessageHandler(state.window, nativeHandlerName, messageCb,
        cast[pointer](state)) == 0:
      raise newException(DarwinBackendError,
          "viewy_darwin_set_message_handler failed")
  state.handlerRegistered = true
  state.bindings.add Binding(name: name, cb: cb)
  viewyDarwinWindowEval(state.window, bindScript(name).cstring)

proc unbind(h: BackendHandle; name: string) =
  let state = h.toState
  state.assertUiThread
  state.removeBinding(name)
  viewyDarwinWindowEval(state.window,
      jsCall("delete window[" & name.toJson() & "];").cstring)

proc resolve(h: BackendHandle; id: string; ok: bool; jsonResult: string) =
  viewyDarwinResolve(h.toState.window, id.cstring, (if ok: 1'i32 else: 0'i32),
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
    caps: {capWindowEvents},
    onWindowEventImpl: onWindowEvent,
  )
