when not defined(viewyGeneratedAssets):
  echo "skipped release embedded asset window: compile with -d:viewyGeneratedAssets"
else:
  import std/os

  import jsony

  import viewy/assets
  import viewy/backend/wv/backend
  import viewy/runtime_js

  var
    windowHandle {.global.}: BackendHandle
    reportSeen {.global.}: bool
    reportContent {.global.}: string

  proc reportCallback(id, jsonArgs: string) {.gcsafe.} =
    {.cast(gcsafe).}:
      let args = jsonArgs.fromJson(seq[string])
      if args.len == 1:
        reportSeen = true
        reportContent = args[0]
    dispatchResolve(windowHandle, id, true, "true")
    dispatchTerminate(windowHandle)

  if getEnv("VIEWY_SKIP_WINDOWED") == "1":
    echo "skipped release embedded asset window: VIEWY_SKIP_WINDOWED=1"
  else:
    let b = newBackend()
    let h = b.create(false)
    windowHandle = h
    b.setTitle(h, "viewy embedded release asset test")
    b.init(h, viewyRuntimeJs)
    b.bindFn(h, "report", reportCallback)
    b.setHtml(h, embeddedHtml())
    b.run(h)
    b.destroy(h)

    doAssert reportSeen
    doAssert reportContent == "embedded release fixture"

    echo "ok: release embedded single-file assets"
