import std/[os, strutils]

import viewy/backend/api
import viewy/backend/select

when selectedBackend != "native" or capTray notin selectedBackendCaps:
  {.error: "examples/tray-app requires -d:viewyBackend=native on macOS, Linux, or Windows".}

const
  trayId = "viewy-tray"
  trayTitle = "viewy tray"

let
  exampleRoot = currentSourcePath().parentDir.parentDir
  colorIconPath = exampleRoot / "assets" / "viewy-tray.svg"
  templateIconPath = exampleRoot / "assets" / "viewy-tray-symbolic.svg"

var
  backend = newBackend()
  handle: BackendHandle
  useTemplateIcon = false
  windowVisible = false

proc platformColorIcon(): string =
  when defined(windows) or defined(macosx):
    ""
  else:
    colorIconPath

proc platformTemplateIcon(): string =
  when defined(windows) or defined(macosx):
    ""
  else:
    templateIconPath

proc trayMenu(): seq[MenuItem] =
  result = @[]
  result.add MenuItem(
    id: if windowVisible: "hide-window" else: "show-window",
    label: if windowVisible: "Hide window" else: "Show window",
    kind: miCommand,
    enabled: true,
  )
  result.add MenuItem(kind: miSeparator)
  when defined(linux):
    result.add MenuItem(
      id: "toggle-icon",
      label: if useTemplateIcon: "Use color icon" else: "Use template icon",
      kind: miCommand,
      enabled: true,
    )
  result.add @[
    MenuItem(
      id: "state",
      label: when defined(linux):
        if useTemplateIcon: "Template icon active" else: "Color icon active"
      else:
        "Platform default icon",
      kind: miCheckbox,
      enabled: false,
      checked: useTemplateIcon,
    ),
    MenuItem(kind: miSeparator),
    MenuItem(id: "quit", label: "Quit", kind: miCommand, enabled: true),
  ]

proc trayOptions(): TrayOptions =
  TrayOptions(
    id: trayId,
    tooltip: trayTitle,
    iconPath: if useTemplateIcon: "" else: platformColorIcon(),
    templateIconPath: if useTemplateIcon: platformTemplateIcon() else: "",
    menu: trayMenu(),
  )

proc updateTray() =
  backend.trayUpdate(handle, trayId, trayOptions())

proc onTray(id: string) {.gcsafe.} =
  {.cast(gcsafe).}:
    case id
    of "toggle-icon":
      useTemplateIcon = not useTemplateIcon
      updateTray()
    of "show-window":
      windowVisible = true
      backend.showWindow(handle)
      updateTray()
    of "hide-window":
      windowVisible = false
      backend.hideWindow(handle)
      updateTray()
    of "quit":
      backend.dispatchTerminate(handle)
    else:
      discard

const html = """
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>viewy tray</title>
    <style>
      :root {
        color-scheme: light dark;
        font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        color: #182023;
        background: #f4f0e8;
      }

      @media (prefers-color-scheme: dark) {
        :root {
          color: #edf2ef;
          background: #182023;
        }
      }

      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
      }

      main {
        width: min(520px, calc(100vw - 48px));
      }

      h1 {
        margin: 0 0 12px;
        font-size: 28px;
        line-height: 1.1;
        font-weight: 720;
      }

      p {
        margin: 0;
        color: color-mix(in srgb, currentColor 74%, transparent);
        line-height: 1.5;
      }
    </style>
  </head>
  <body>
    <main>
      <h1>viewy tray</h1>
      <p>The app starts hidden. Use the native tray menu to show the window, switch icon mode on Linux, or quit.</p>
    </main>
  </body>
</html>
"""

if capTray notin backend.caps:
  let detail =
    when defined(linux):
      " Install libayatana-appindicator3 and enable a tray host extension."
    else:
      ""
  raise newException(CatchableError,
    "native tray capability is unavailable at runtime." & detail)

handle = backend.create(false)
try:
  backend.setTitle(handle, trayTitle)
  backend.setSize(handle, 460, 280, whMin)
  backend.setHtml(handle, html.strip())
  backend.hideWindow(handle)
  backend.trayCreate(handle, trayOptions(), onTray)
  backend.run(handle)
finally:
  if handle != nil:
    try:
      if capTray in backend.caps:
        backend.trayDestroy(handle, trayId)
    except CatchableError:
      discard
    backend.destroy(handle)
    handle = nil
