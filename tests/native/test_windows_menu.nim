when not defined(windows):
  echo "skipped windows menu: non-Windows host"
else:
  import viewy/backend/native/windows/backend
  import viewy/backend/api

  let nativeBackend = newBackend()

  doAssert capMenu in nativeBackend.caps
  doAssert nativeBackend.setAppMenuImpl != nil

  when defined(nimcheck):
    proc menuCb(id: string) {.gcsafe.} =
      discard id

    let appMenu = @[
      MenuItem(
        id: "file",
        label: "File",
        kind: miSubmenu,
        enabled: true,
        children: @[
          MenuItem(id: "new", label: "New", accelerator: "CmdOrCtrl+N",
            kind: miCommand, enabled: true),
          MenuItem(id: "open", label: "Open", accelerator: "CmdOrCtrl+O",
            kind: miCommand, enabled: true),
          MenuItem(kind: miSeparator),
          MenuItem(id: "quit", label: "Quit", accelerator: "Alt+F4",
            kind: miCommand, enabled: true),
        ],
      ),
      MenuItem(
        id: "view",
        label: "View",
        kind: miSubmenu,
        enabled: true,
        children: @[
          MenuItem(id: "sidebar", label: "Sidebar", kind: miCheckbox,
            enabled: true, checked: true),
        ],
      ),
    ]

    var handle: BackendHandle
    if handle != nil:
      nativeBackend.setAppMenuImpl(handle, appMenu, menuCb)

  echo "ok: windows menu declarations"
