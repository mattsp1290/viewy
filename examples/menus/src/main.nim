import std/[json, strutils]

import viewy/backend/api
import viewy/backend/select
import viewy/runtime_js

import jsony

when selectedBackend != "native" or capMenu notin selectedBackendCaps or
    capContextMenu notin selectedBackendCaps:
  {.error: "examples/menus requires -d:viewyBackend=native on macOS, Linux, or Windows".}

var
  backend = newBackend()
  handle: BackendHandle
  sidebarVisible = true
  theme = "system"

proc jsString(value: string): string =
  value.toJson()

proc menuBar(items: varargs[MenuItem]): seq[MenuItem] =
  @items

proc submenu(label: string; children: varargs[MenuItem]): MenuItem =
  MenuItem(label: label, kind: miSubmenu, enabled: true, children: @children)

proc onMenu(id, label: string; accelerator = ""; enabled = true): MenuItem =
  MenuItem(
    id: id,
    label: label,
    accelerator: accelerator,
    kind: miCommand,
    enabled: enabled,
  )

proc separator(): MenuItem =
  MenuItem(kind: miSeparator)

proc checkbox(id, label: string; accelerator = ""; checked: bool): MenuItem =
  MenuItem(
    id: id,
    label: label,
    accelerator: accelerator,
    kind: miCheckbox,
    enabled: true,
    checked: checked,
  )

proc radio(id, label: string; checked: bool): MenuItem =
  MenuItem(
    id: id,
    label: label,
    kind: miRadio,
    enabled: true,
    checked: checked,
  )

proc updateStatus(message: string) =
  if handle != nil:
    backend.dispatchEval(handle,
      "window.setMenuStatus && window.setMenuStatus(" & message.jsString() & ");")

proc menuItems(): seq[MenuItem] =
  menuBar(
    submenu("File",
      onMenu("new-note", "New Note", "CmdOrCtrl+N"),
      onMenu("open", "Open", "CmdOrCtrl+O"),
      separator(),
      onMenu("quit", "Quit",
        when defined(macosx): "CmdOrCtrl+Q" else: "Alt+F4"),
    ),
    submenu("View",
      checkbox("toggle-sidebar", "Sidebar", "CmdOrCtrl+B", sidebarVisible),
      separator(),
      radio("theme-system", "System", theme == "system"),
      radio("theme-light", "Light", theme == "light"),
      radio("theme-dark", "Dark", theme == "dark"),
    ),
    submenu("Tools",
      onMenu("inspect", "Inspect Selection", "CmdOrCtrl+Shift+I"),
      onMenu("disabled", "Disabled Item", enabled = false),
    ),
  )

proc contextItems(): seq[MenuItem] =
  menuBar(
    onMenu("ctx-copy", "Copy", "CmdOrCtrl+C"),
    onMenu("ctx-paste", "Paste", "CmdOrCtrl+V"),
    separator(),
    onMenu("ctx-inspect", "Inspect Here"),
  )

proc installMenu()

proc handleCommand(id: string) {.gcsafe.} =
  {.cast(gcsafe).}:
    case id
    of "quit":
      backend.dispatchTerminate(handle)
    of "toggle-sidebar":
      sidebarVisible = not sidebarVisible
      installMenu()
      updateStatus("Sidebar " & (if sidebarVisible: "shown" else: "hidden"))
    of "theme-system", "theme-light", "theme-dark":
      theme = id.replace("theme-", "")
      installMenu()
      updateStatus("Theme set to " & theme)
    else:
      updateStatus("Menu command: " & id)

proc installMenu() =
  backend.setAppMenu(handle, menuItems(), handleCommand)

proc showExampleContextMenu() =
  if capContextMenu notin backend.caps:
    updateStatus("Context menu requested, but this runtime does not advertise capContextMenu yet")
    return
  backend.showContextMenu(handle, ContextMenuOptions(
    menu: contextItems(),
    x: 32,
    y: 120,
  ), handleCommand)

proc onContextRequest(id, jsonArgs: string) {.gcsafe.} =
  {.cast(gcsafe).}:
    try:
      discard parseJson(jsonArgs)
      showExampleContextMenu()
      backend.resolve(handle, id, true, "")
    except CatchableError as error:
      updateStatus("Context menu failed: " & error.msg)
      backend.resolve(handle, id, false, error.msg.toJson())

const html = """
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>viewy menus</title>
    <style>
      :root {
        color-scheme: light dark;
        font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        color: #1d2528;
        background: #f6f7f4;
      }

      @media (prefers-color-scheme: dark) {
        :root {
          color: #edf2ef;
          background: #151b1d;
        }
      }

      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
      }

      main {
        width: min(620px, calc(100vw - 48px));
        display: grid;
        gap: 18px;
      }

      h1 {
        margin: 0;
        font-size: 30px;
        line-height: 1.1;
        font-weight: 720;
      }

      p {
        margin: 0;
        color: color-mix(in srgb, currentColor 72%, transparent);
        line-height: 1.5;
      }

      #surface {
        min-height: 180px;
        border: 1px solid color-mix(in srgb, currentColor 20%, transparent);
        border-radius: 8px;
        display: grid;
        place-items: center;
        padding: 24px;
        background: color-mix(in srgb, currentColor 4%, transparent);
      }

      #status {
        font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
        font-size: 13px;
      }
    </style>
  </head>
  <body>
    <main>
      <div>
        <h1>viewy menus</h1>
        <p>Use the native menu bar or right-click inside the target area.</p>
      </div>
      <section id="surface">
        <p id="status">Ready</p>
      </section>
    </main>
    <script>
      window.setMenuStatus = function(message) {
        document.getElementById("status").textContent = message;
      };

      document.getElementById("surface").addEventListener("contextmenu", function(event) {
        event.preventDefault();
        if (window.__viewy) {
          window.__viewy.call("viewyShowContextMenu").catch(function(error) {
            window.setMenuStatus("Context menu failed: " + error);
          });
        }
      });
    </script>
  </body>
</html>
"""

if capMenu notin backend.caps:
  raise newException(CatchableError,
    "native menu capability is unavailable at runtime")

handle = backend.create(false)
try:
  backend.setTitle(handle, "viewy menus")
  backend.setSize(handle, 700, 460, whMin)
  backend.init(handle, viewyRuntimeJs)
  backend.bindFn(handle, "viewyShowContextMenu", onContextRequest)
  installMenu()
  backend.setHtml(handle, html.strip())
  backend.run(handle)
finally:
  if handle != nil:
    backend.destroy(handle)
    handle = nil
