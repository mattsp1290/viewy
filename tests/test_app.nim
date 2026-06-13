import std/asyncdispatch

import jsony

import viewy
import viewy/backend/api

clearBindingsForTests()

expose addOne(value: int): int =
  value + 1

proc delayedValue(value: int): Future[int] {.async.} =
  await sleepAsync(75)
  value

expose slowAddOne(value: int): Future[int] =
  delayedValue(value + 1)

var
  createdDebug = false
  destroyed = false
  runShouldRaise = false
  titleSeen = ""
  sizeSeen: tuple[width, height: int; hints: WindowHints]
  initSeen = ""
  htmlSeen = ""
  navigatedTo = ""
  registeredScheme = ""
  registeredAssetPath = ""
  boundNames: seq[string]
  boundCallbacks: seq[BindCallback]
  resolvedIds: seq[string]
  resolvedOk: seq[bool]
  resolvedJson: seq[string]

let fakeHandle = cast[BackendHandle](0x2)

proc fakeCreate(debug: bool): BackendHandle =
  createdDebug = debug
  fakeHandle

proc fakeDestroy(h: BackendHandle) =
  doAssert h == fakeHandle
  destroyed = true

proc fakeRun(h: BackendHandle) =
  doAssert h == fakeHandle
  if runShouldRaise:
    raise newException(ValueError, "run failed")

  for i, name in boundNames:
    if name == "addOne":
      boundCallbacks[i]("rpc-sync", "[2]")
    elif name == "slowAddOne":
      boundCallbacks[i]("rpc-async", "[4]")

proc fakeTerminate(h: BackendHandle) {.gcsafe.} =
  discard h

proc fakeDispatch(h: BackendHandle; fn: DispatchProc) {.gcsafe.} =
  doAssert h == fakeHandle
  fn()

proc fakeDispatchEval(h: BackendHandle; js: string) {.gcsafe.} =
  discard h
  discard js

proc fakeDispatchResolve(h: BackendHandle; id: string; ok: bool;
    jsonResult: string) {.gcsafe.} =
  doAssert h == fakeHandle
  {.cast(gcsafe).}:
    resolvedIds.add id
    resolvedOk.add ok
    resolvedJson.add jsonResult

proc fakeSetTitle(h: BackendHandle; title: string) =
  doAssert h == fakeHandle
  titleSeen = title

proc fakeSetSize(h: BackendHandle; width, height: int; hints: WindowHints) =
  doAssert h == fakeHandle
  sizeSeen = (width, height, hints)

proc fakeNavigate(h: BackendHandle; url: string) =
  doAssert h == fakeHandle
  navigatedTo = url

proc fakeRegisterScheme(h: BackendHandle; scheme: string;
    handler: AssetHandler) =
  doAssert h == fakeHandle
  registeredScheme = scheme
  let response = handler(AssetRequest(
    scheme: scheme,
    httpMethod: "POST",
    path: "/assets/app.js",
    query: "v=1",
    headers: @[(name: "Accept", value: "*/*")],
    body: "payload",
  ))
  doAssert response.status == 200
  registeredAssetPath = response.body

proc fakeSetHtml(h: BackendHandle; html: string) =
  doAssert h == fakeHandle
  htmlSeen = html

proc fakeInit(h: BackendHandle; js: string) =
  doAssert h == fakeHandle
  initSeen = js

proc fakeBindFn(h: BackendHandle; name: string; cb: BindCallback) =
  doAssert h == fakeHandle
  boundNames.add name
  boundCallbacks.add cb

proc fakeUnbind(h: BackendHandle; name: string) =
  discard h
  discard name

proc fakeResolve(h: BackendHandle; id: string; ok: bool; jsonResult: string) =
  discard h
  discard id
  discard ok
  discard jsonResult

let fakeBackend = Backend(
  create: fakeCreate,
  destroy: fakeDestroy,
  run: fakeRun,
  terminate: fakeTerminate,
  dispatch: fakeDispatch,
  dispatchEval: fakeDispatchEval,
  dispatchResolve: fakeDispatchResolve,
  setTitle: fakeSetTitle,
  setSize: fakeSetSize,
  navigate: fakeNavigate,
  setHtml: fakeSetHtml,
  eval: fakeDispatchEval,
  init: fakeInit,
  bindFn: fakeBindFn,
  unbind: fakeUnbind,
  resolve: fakeResolve,
  caps: {capScheme},
  registerSchemeImpl: fakeRegisterScheme,
)

let compileOnlyAssetHandler =
  proc(request: AssetRequest): AssetResponse {.gcsafe.} =
    doAssert request.path.len >= 0
    assetResponse(404, "Not Found", "text/plain; charset=utf-8", "not found")

discard newApp(assetHandler = compileOnlyAssetHandler, backend = fakeBackend)

proc resetState() =
  createdDebug = false
  destroyed = false
  runShouldRaise = false
  titleSeen = ""
  sizeSeen = (0, 0, whNone)
  initSeen = ""
  htmlSeen = ""
  navigatedTo = ""
  registeredScheme = ""
  registeredAssetPath = ""
  boundNames.setLen 0
  boundCallbacks.setLen 0
  resolvedIds.setLen 0
  resolvedOk.setLen 0
  resolvedJson.setLen 0

proc resolvedJsonFor(id: string): string =
  for i, item in resolvedIds:
    if item == id:
      doAssert resolvedOk[i]
      return resolvedJson[i]
  raise newException(ValueError, "missing resolved id: " & id)

resetState()

let app = newApp(title = "Test App", width = 640, height = 480,
    resizable = false, html = "<main>hello</main>", debug = true,
    backend = fakeBackend)

app.run()

doAssert createdDebug
doAssert destroyed
doAssert app.handle == nil
doAssert titleSeen == "Test App"
doAssert sizeSeen == (640, 480, whFixed)
doAssert initSeen == viewyRuntimeJs
doAssert htmlSeen == "<main>hello</main>"
doAssert navigatedTo == ""
doAssert boundNames == @["addOne", "slowAddOne"]
doAssert resolvedJsonFor("rpc-sync").fromJson(int) == 3
doAssert resolvedJsonFor("rpc-async").fromJson(int) == 5

resetState()

let embeddedApp = newApp(backend = fakeBackend)
embeddedApp.run()

doAssert destroyed
doAssert htmlSeen == fallbackEmbeddedHtml
doAssert navigatedTo == ""

resetState()

let emptyHtmlApp = newApp(html = "", backend = fakeBackend)
emptyHtmlApp.run()

doAssert destroyed
doAssert htmlSeen == ""
doAssert navigatedTo == ""

resetState()

let devApp = newApp(assets = assetsDevServer, devUrl = "http://127.0.0.1:7777",
    backend = fakeBackend)
devApp.run()

doAssert destroyed
doAssert htmlSeen == ""
doAssert navigatedTo == "http://127.0.0.1:7777"

resetState()

when selectedBackend == "native":
  let schemeHandler =
    proc(request: AssetRequest): AssetResponse {.gcsafe.} =
      doAssert request.scheme == "viewy"
      doAssert request.httpMethod == "POST"
      doAssert request.path == "/assets/app.js"
      doAssert request.query == "v=1"
      doAssert request.body == "payload"
      assetResponse(200, "OK", "text/javascript; charset=utf-8", request.path)

  let schemeApp = newApp(assets = assetsScheme, assetHandler = schemeHandler,
      backend = fakeBackend)
  schemeApp.run()

  doAssert destroyed
  doAssert registeredScheme == "viewy"
  doAssert registeredAssetPath == "/assets/app.js"
  doAssert navigatedTo == "viewy://app/"
  doAssert htmlSeen == ""

  resetState()

runShouldRaise = true

let failingApp = newApp(backend = fakeBackend)
try:
  failingApp.run()
  doAssert false, "run should raise"
except ValueError:
  discard

doAssert destroyed
doAssert failingApp.handle == nil

echo "ok: app high-level run wiring"
