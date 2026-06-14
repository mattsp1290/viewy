import viewy/app
import viewy/backend/api

var
  subscribed = false
  seenKinds: seq[WindowEventKind]
  seenSizes: seq[(int, int)]
  destroyed = false

let fakeHandle = cast[BackendHandle](0x8)

proc fakeCreate(debug: bool): BackendHandle =
  doAssert not debug
  fakeHandle

proc fakeDestroy(h: BackendHandle) =
  doAssert h == fakeHandle
  destroyed = true

proc fakeRun(h: BackendHandle) =
  doAssert h == fakeHandle

proc fakeSetTitle(h: BackendHandle; title: string) =
  doAssert h == fakeHandle
  doAssert title == "events"

proc fakeSetSize(h: BackendHandle; width, height: int; hints: WindowHints) =
  doAssert h == fakeHandle
  doAssert width == 320
  doAssert height == 240
  doAssert hints == whNone

proc fakeSetHtml(h: BackendHandle; html: string) =
  doAssert h == fakeHandle
  doAssert html.len > 0

proc fakeInit(h: BackendHandle; js: string) =
  doAssert h == fakeHandle
  doAssert js.len > 0

proc fakeBindFn(h: BackendHandle; name: string; cb: BindCallback) =
  discard h
  discard name
  doAssert not cb.isNil

proc fakeOnWindowEvent(h: BackendHandle; cb: WindowEventCallback) =
  doAssert h == fakeHandle
  subscribed = true
  cb(WindowEvent(kind: weResize, width: 320, height: 240))
  cb(WindowEvent(kind: weClose))

let eventBackend = Backend(
  create: fakeCreate,
  destroy: fakeDestroy,
  run: fakeRun,
  setTitle: fakeSetTitle,
  setSize: fakeSetSize,
  setHtml: fakeSetHtml,
  init: fakeInit,
  bindFn: fakeBindFn,
  caps: {capWindowEvents},
  onWindowEventImpl: fakeOnWindowEvent,
)

let lifecycleApp = newApp(title = "events", width = 320, height = 240,
    html = "<main>events</main>", backend = eventBackend)

lifecycleApp.onWindowEvent(proc(event: WindowEvent) {.gcsafe.} =
  {.cast(gcsafe).}:
    seenKinds.add event.kind
    seenSizes.add((event.width, event.height))
)

lifecycleApp.on(weClose, proc(event: WindowEvent) {.gcsafe.} =
  doAssert event.kind == weClose
  {.cast(gcsafe).}:
    seenKinds.add event.kind
)

lifecycleApp.run()

doAssert subscribed
doAssert destroyed
doAssert seenKinds == @[weResize, weClose, weClose]
doAssert seenSizes == @[(320, 240), (0, 0)]
doAssert lifecycleApp.handle == nil

let missingCapBackend = Backend(
  create: fakeCreate,
  destroy: fakeDestroy,
  run: fakeRun,
  setTitle: fakeSetTitle,
  setSize: fakeSetSize,
  setHtml: fakeSetHtml,
  init: fakeInit,
  bindFn: fakeBindFn,
  caps: {},
)

let unsupported = newApp(title = "events", width = 320, height = 240,
    html = "<main>events</main>", backend = missingCapBackend)
unsupported.onWindowEvent(proc(event: WindowEvent) {.gcsafe.} =
  discard event
)

destroyed = false
var rejected = false
try:
  unsupported.run()
except AssertionDefect:
  rejected = true

doAssert rejected
doAssert destroyed

echo "ok: app window lifecycle events"
