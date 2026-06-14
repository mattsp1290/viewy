when not defined(linux):
  echo "skipped linux menu: non-linux host"
else:
  import viewy/backend/api
  import viewy/backend/native/linux/backend

  let nativeBackend = newBackend()

  doAssert capMenu in nativeBackend.caps
  doAssert nativeBackend.setAppMenuImpl != nil

  when defined(nimcheck):
    let handle = cast[BackendHandle](0x9)
    var seen = ""
    proc menuCb(id: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        seen = id

    nativeBackend.setAppMenuImpl(handle, @[
      MenuItem(
        id: "file",
        label: "File",
        kind: miSubmenu,
        enabled: true,
        children: @[
          MenuItem(id: "new", label: "New", accelerator: "CmdOrCtrl+N",
            kind: miCommand, enabled: true),
          MenuItem(id: "zoom", label: "Zoom", accelerator: "CmdOrCtrl+Plus",
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
          MenuItem(id: "light", label: "Light", kind: miRadio,
            enabled: true, checked: true),
          MenuItem(id: "dark", label: "Dark", kind: miRadio, enabled: true),
      ],
    ),
    ], menuCb)
    doAssert seen.len == 0

  echo "ok: linux menu declarations"
