when not defined(windows):
  echo "skipped windows backend lifecycle: non-Windows host"
else:
  import viewy/backend/native/windows/backend
  import viewy/backend/api

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
  doAssert nativeBackend.caps == {capScheme, capMenu, capTray, capWindowVisibility}
  doAssert nativeBackend.registerSchemeImpl != nil
  doAssert nativeBackend.setAppMenuImpl != nil
  doAssert nativeBackend.trayCreateImpl != nil
  doAssert nativeBackend.trayUpdateImpl != nil
  doAssert nativeBackend.trayDestroyImpl != nil
  doAssert nativeBackend.showWindowImpl != nil
  doAssert nativeBackend.hideWindowImpl != nil

  when defined(nimcheck):
    var handle: BackendHandle
    if handle != nil:
      proc trayCb(id: string) {.gcsafe.} =
        discard id
      proc menuCb(id: string) {.gcsafe.} =
        discard id

      nativeBackend.setTitle(handle, "Viewy")
      nativeBackend.setSize(handle, 800, 600, whNone)
      nativeBackend.hideWindowImpl(handle)
      nativeBackend.showWindowImpl(handle)
      nativeBackend.navigate(handle, "https://example.test/")
      nativeBackend.setHtml(handle, "<!doctype html><title>Viewy</title>")
      nativeBackend.init(handle, "window.__viewyInit = true;")
      nativeBackend.eval(handle, "window.__viewyEval = true;")
      nativeBackend.setAppMenuImpl(handle, @[
        MenuItem(
          id: "file",
          label: "File",
          kind: miSubmenu,
          enabled: true,
          children: @[
            MenuItem(id: "open", label: "Open", accelerator: "CmdOrCtrl+O",
              kind: miCommand, enabled: true),
            MenuItem(kind: miSeparator),
            MenuItem(id: "quit", label: "Quit", accelerator: "CmdOrCtrl+Q",
              kind: miCommand, enabled: true),
        ],
      ),
      ], menuCb)
      nativeBackend.trayCreateImpl(handle, TrayOptions(
        id: "main",
        tooltip: "Viewy",
        menu: @[
          MenuItem(id: "open", label: "Open", kind: miCommand, enabled: true),
          MenuItem(kind: miSeparator),
          MenuItem(id: "quit", label: "Quit", kind: miCommand, enabled: true),
        ],
      ), trayCb)
      nativeBackend.trayUpdateImpl(handle, "main", TrayOptions(
        id: "main",
        tooltip: "Updated",
        menu: @[
          MenuItem(id: "open", label: "Open", kind: miCommand, enabled: true),
        ],
      ))
      nativeBackend.trayDestroyImpl(handle, "main")
      nativeBackend.dispatchEval(handle, "window.__viewyDispatch = true;")
      nativeBackend.dispatchResolve(handle, "1", true, "{}")
      nativeBackend.dispatchTerminate(handle)
      nativeBackend.terminate(handle)

  echo "ok: windows backend lifecycle declarations"
