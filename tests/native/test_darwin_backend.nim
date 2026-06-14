when not defined(macosx):
  echo "skipped darwin native backend: non-macOS host"
else:
  import std/os

  import viewy/backend/api
  import viewy/backend/native/darwin/backend

  let nativeBackend = newBackend()

  doAssert nativeBackend.create != nil
  doAssert nativeBackend.destroy != nil
  doAssert nativeBackend.run != nil
  doAssert nativeBackend.terminate != nil
  doAssert nativeBackend.dispatch != nil
  doAssert nativeBackend.dispatchEval != nil
  doAssert nativeBackend.dispatchResolve != nil
  doAssert nativeBackend.dispatchTerminate != nil
  doAssert nativeBackend.setTitle != nil
  doAssert nativeBackend.setSize != nil
  doAssert nativeBackend.navigate != nil
  doAssert nativeBackend.setHtml != nil
  doAssert nativeBackend.eval != nil
  doAssert nativeBackend.init != nil
  doAssert nativeBackend.bindFn != nil
  doAssert nativeBackend.unbind != nil
  doAssert nativeBackend.resolve != nil
  doAssert nativeBackend.caps == {capScheme, capMenu, capTray, capWindowEvents,
      capWindowVisibility}
  doAssert nativeBackend.onWindowEventImpl != nil
  doAssert nativeBackend.registerSchemeImpl != nil
  doAssert nativeBackend.setAppMenuImpl != nil
  doAssert nativeBackend.trayCreateImpl != nil
  doAssert nativeBackend.trayUpdateImpl != nil
  doAssert nativeBackend.trayDestroyImpl != nil
  doAssert nativeBackend.showWindowImpl != nil
  doAssert nativeBackend.hideWindowImpl != nil

  if getEnv("VIEWY_NATIVE_DARWIN_SMOKE") == "1":
    let h = nativeBackend.create(false)
    var dispatched = false
    nativeBackend.dispatch(h, proc() {.gcsafe.} =
      dispatched = true
    )
    nativeBackend.bindFn(h, "viewySmoke", proc(id,
        jsonArgs: string) {.gcsafe.} =
      discard id
      discard jsonArgs
    )
    nativeBackend.setTitle(h, "Viewy Darwin native smoke")
    nativeBackend.setSize(h, 320, 240, whMin)
    nativeBackend.hideWindow(h)
    nativeBackend.showWindow(h)
    nativeBackend.setHtml(h, "<!doctype html><p>viewy native macOS</p>")
    nativeBackend.setAppMenu(h, @[MenuItem(
      id: "app",
      label: "App",
      kind: miSubmenu,
      enabled: true,
      children: @[MenuItem(id: "quit", label: "Quit",
        accelerator: "CmdOrCtrl+Q", kind: miCommand, enabled: true)]
    )], proc(id: string) {.gcsafe.} =
      discard id
    )
    doAssertRaises(DarwinBackendError):
      nativeBackend.setAppMenu(h, @[MenuItem(id: "bad", label: "Bad",
        accelerator: "CmdOrCtrl+UnknownKey", kind: miCommand,
        enabled: true)], proc(id: string) {.gcsafe.} =
        discard id
      )
    nativeBackend.trayCreate(h, TrayOptions(
      id: "main",
      tooltip: "Viewy",
      menu: @[MenuItem(id: "quit", label: "Quit", kind: miCommand,
        enabled: true)]
    ), proc(id: string) {.gcsafe.} =
      discard id
    )
    nativeBackend.trayUpdate(h, "main", TrayOptions(id: "main",
      tooltip: "Viewy updated"))
    nativeBackend.trayCreate(h, TrayOptions(
      id: "secondary",
      tooltip: "Viewy secondary",
      menu: @[MenuItem(id: "show", label: "Show", kind: miCommand,
        enabled: true)]
    ), proc(id: string) {.gcsafe.} =
      discard id
    )
    doAssertRaises(DarwinBackendError):
      nativeBackend.trayCreate(h, TrayOptions(id: "main"), proc(
          id: string) {.gcsafe.} =
        discard id
      )
    nativeBackend.trayDestroy(h, "secondary")
    nativeBackend.trayDestroy(h, "main")
    doAssertRaises(DarwinBackendError):
      nativeBackend.registerScheme(h, "late", proc(
          request: AssetRequest): AssetResponse {.gcsafe.} =
        discard request
        AssetResponse(status: 200, statusText: "OK",
          mimeType: "text/plain", body: "")
      )
    nativeBackend.dispatchTerminate(h)
    nativeBackend.run(h)
    doAssert dispatched
    nativeBackend.destroy(h)
    doAssertRaises(DarwinBackendError):
      nativeBackend.dispatchTerminate(h)

  echo "ok: darwin native backend declarations"
