import viewy

when defined(viewyGeneratedAssets) or defined(viewyGeneratedServedAssets) or
    defined(viewyGeneratedSchemeAssets):
  import std/os
  import viewy/backend/select

when defined(viewyGeneratedServedAssets) or defined(viewyGeneratedSchemeAssets):
  import viewy/assets_served

when isMainModule:
  when defined(viewyGeneratedAssets) or defined(viewyGeneratedServedAssets) or
      defined(viewyGeneratedSchemeAssets):
    if getEnv("VIEWY_E2E_QUIT") == "1":
      when defined(viewyGeneratedServedAssets) or defined(viewyGeneratedSchemeAssets):
        let server = startGeneratedServedServer()
        defer: server.stop()
      let b = newBackend()
      let h = b.create(false)
      b.setTitle(h, "viewy app")
      b.init(h, viewyRuntimeJs)
      when defined(viewyGeneratedAssets):
        b.setHtml(h, embeddedHtml())
      else:
        b.navigate(h, server.documentUrl())
      b.dispatchTerminate(h)
      b.run(h)
      b.destroy(h)
    else:
      newApp(title = "viewy app").run()
  else:
    newApp(title = "viewy app").run()
