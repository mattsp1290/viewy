import viewy

when defined(viewyGeneratedAssets):
  import std/os
  import viewy/backend/lite/backend

when isMainModule:
  when defined(viewyGeneratedAssets):
    if getEnv("VIEWY_E2E_QUIT") == "1":
      let b = newBackend()
      let h = b.create(false)
      b.setTitle(h, "viewy app")
      b.init(h, viewyRuntimeJs)
      b.setHtml(h, embeddedHtml())
      dispatchTerminate(h)
      b.run(h)
      b.destroy(h)
    else:
      newApp(title = "viewy app").run()
  else:
    newApp(title = "viewy app").run()
