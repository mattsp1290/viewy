when not defined(viewyGeneratedAssets):
  echo "skipped release embedded asset window: compile with -d:viewyGeneratedAssets"
else:
  import std/os

  import jsony

  import viewy/assets
  import viewy/backend/api
  import viewy/backend/select
  import viewy/runtime_js

  var
    backend {.global.}: Backend
    windowHandle {.global.}: BackendHandle
    reportSeen {.global.}: bool
    reportContent {.global.}: string

  proc reportCallback(id, jsonArgs: string) {.gcsafe.} =
    {.cast(gcsafe).}:
      let args = jsonArgs.fromJson(seq[string])
      if args.len == 1:
        reportSeen = true
        reportContent = args[0]
      backend.dispatchResolve(windowHandle, id, true, "true")
      backend.dispatchTerminate(windowHandle)

  if getEnv("VIEWY_SKIP_WINDOWED") == "1":
    echo "skipped release embedded asset window: VIEWY_SKIP_WINDOWED=1"
  else:
    backend = newBackend()
    let h = backend.create(false)
    windowHandle = h
    backend.setTitle(h, "viewy embedded release asset test")
    backend.init(h, viewyRuntimeJs)
    backend.bindFn(h, "report", reportCallback)
    backend.setHtml(h, embeddedHtml())
    backend.run(h)
    backend.destroy(h)

    doAssert reportSeen
    doAssert reportContent == "embedded release fixture"

    echo "ok: release embedded single-file assets"
