when not defined(viewyDev):
  echo "skipped app dev define test: compile with -d:viewyDev=<url>"
else:
  import viewy
  import viewy/backend/api

  var
    createdDebug = false
    destroyed = false
    navigatedTo = ""
    htmlSeen = ""

  let fakeHandle = cast[BackendHandle](0x4)

  proc fakeCreate(debug: bool): BackendHandle =
    createdDebug = debug
    fakeHandle

  proc fakeDestroy(h: BackendHandle) =
    doAssert h == fakeHandle
    destroyed = true

  proc fakeRun(h: BackendHandle) =
    doAssert h == fakeHandle

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
    discard h
    discard id
    discard ok
    discard jsonResult

  proc fakeSetTitle(h: BackendHandle; title: string) =
    discard title
    doAssert h == fakeHandle

  proc fakeSetSize(h: BackendHandle; width, height: int; hints: WindowHints) =
    discard width
    discard height
    discard hints
    doAssert h == fakeHandle

  proc fakeNavigate(h: BackendHandle; url: string) =
    doAssert h == fakeHandle
    navigatedTo = url

  proc fakeSetHtml(h: BackendHandle; html: string) =
    doAssert h == fakeHandle
    htmlSeen = html

  proc fakeInit(h: BackendHandle; js: string) =
    discard js
    doAssert h == fakeHandle

  proc fakeBindFn(h: BackendHandle; name: string; cb: BindCallback) =
    discard name
    doAssert h == fakeHandle

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
  )

  let app = newApp(html = "<main>embedded</main>",
      devUrl = "http://runtime.example.invalid:9999",
      debug = true,
      backend = fakeBackend)
  app.run()

  doAssert viewyDevUrl == "http://127.0.0.1:5174"
  doAssert createdDebug
  doAssert destroyed
  doAssert htmlSeen == ""
  doAssert navigatedTo == "http://127.0.0.1:5174"

  echo "ok: app dev strdefine URL"
