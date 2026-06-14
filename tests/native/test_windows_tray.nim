when not defined(windows):
  echo "skipped windows tray: non-Windows host"
else:
  import viewy/backend/native/windows/backend
  import viewy/backend/api

  let nativeBackend = newBackend()

  doAssert capTray in nativeBackend.caps
  doAssert nativeBackend.trayCreateImpl != nil
  doAssert nativeBackend.trayUpdateImpl != nil
  doAssert nativeBackend.trayDestroyImpl != nil

  when defined(nimcheck):
    proc trayCb(id: string) {.gcsafe.} =
      discard id

    let menu = @[
      MenuItem(id: "show", label: "Show", kind: miCommand, enabled: true),
      MenuItem(
        id: "mode",
        label: "Mode",
        kind: miSubmenu,
        enabled: true,
        children: @[
          MenuItem(id: "light", label: "Light", kind: miRadio, enabled: true,
            checked: true),
          MenuItem(id: "dark", label: "Dark", kind: miRadio, enabled: true),
        ],
      ),
      MenuItem(kind: miSeparator),
      MenuItem(id: "quit", label: "Quit", kind: miCommand, enabled: true),
    ]

    let options = TrayOptions(
      id: "main",
      tooltip: "Viewy",
      iconPath: "tray-light.ico",
      templateIconPath: "tray-dark.ico",
      menu: menu,
    )
    var handle: BackendHandle
    if handle != nil:
      nativeBackend.trayCreateImpl(handle, options, trayCb)
      nativeBackend.trayUpdateImpl(handle, "main", TrayOptions(
        id: "main",
        tooltip: "Viewy updated",
        templateIconPath: "tray-dark.ico",
        menu: menu,
      ))
      nativeBackend.trayDestroyImpl(handle, "main")

  echo "ok: windows tray declarations"
