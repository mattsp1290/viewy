import std/[os, osproc, strutils]

import viewy/backend/api
import viewy/backend/wv/backend

let fakeHandle = cast[BackendHandle](0x6)

var
  schemeSeen = ""
  assetPathSeen = ""
  menuIds: seq[string]
  trayIds: seq[string]
  windowEvents: seq[WindowEventKind]
  terminated = false

proc fakeCreate(debug: bool): BackendHandle =
  doAssert not debug
  fakeHandle

proc fakeRegisterScheme(h: BackendHandle; scheme: string;
    handler: AssetHandler) =
  doAssert h == fakeHandle
  schemeSeen = scheme
  let response = handler(AssetRequest(
    scheme: scheme,
    httpMethod: "GET",
    path: "/index.html",
    query: "",
    headers: @[(name: "Accept", value: "text/html")],
    body: "",
  ))
  doAssert response.status == 200
  doAssert response.mimeType == "text/html"
  assetPathSeen = response.body

proc fakeDispatchTerminate(h: BackendHandle) {.gcsafe.} =
  doAssert h == fakeHandle
  {.cast(gcsafe).}:
    terminated = true

proc fakeSetAppMenu(h: BackendHandle; menu: seq[MenuItem];
    cb: MenuCallback) =
  doAssert h == fakeHandle
  doAssert menu.len == 1
  doAssert menu[0].kind == miSubmenu
  doAssert menu[0].children[0].accelerator == "CmdOrCtrl+Q"
  cb(menu[0].children[0].id)

proc fakeTrayCreate(h: BackendHandle; options: TrayOptions;
    cb: MenuCallback) =
  doAssert h == fakeHandle
  doAssert options.tooltip == "Viewy"
  trayIds.add options.id
  cb(options.menu[0].id)

proc fakeTrayUpdate(h: BackendHandle; id: string; options: TrayOptions) =
  doAssert h == fakeHandle
  doAssert id == options.id
  trayIds.add id & ":updated"

proc fakeTrayDestroy(h: BackendHandle; id: string) =
  doAssert h == fakeHandle
  trayIds.add id & ":destroyed"

proc fakeOnWindowEvent(h: BackendHandle; cb: WindowEventCallback) =
  doAssert h == fakeHandle
  cb(WindowEvent(kind: weResize, width: 640, height: 480))

let fakeBackend = Backend(
  create: fakeCreate,
  dispatchTerminate: fakeDispatchTerminate,
  caps: {capScheme, capMenu, capTray, capWindowEvents},
  registerSchemeImpl: fakeRegisterScheme,
  setAppMenuImpl: fakeSetAppMenu,
  trayCreateImpl: fakeTrayCreate,
  trayUpdateImpl: fakeTrayUpdate,
  trayDestroyImpl: fakeTrayDestroy,
  onWindowEventImpl: fakeOnWindowEvent,
)

let h = fakeBackend.create(false)
fakeBackend.dispatchTerminate(h)

proc handleAsset(request: AssetRequest): AssetResponse {.gcsafe.} =
  doAssert request.scheme == "viewy"
  doAssert request.path == "/index.html"
  AssetResponse(
    status: 200,
    statusText: "OK",
    mimeType: "text/html",
    headers: @[(name: "Cache-Control", value: "no-store")],
    body: request.path,
  )

let quitItem = MenuItem(
  id: "quit",
  label: "Quit",
  accelerator: "CmdOrCtrl+Q",
  kind: miCommand,
  enabled: true,
)
let fileMenu = MenuItem(
  id: "file",
  label: "File",
  kind: miSubmenu,
  enabled: true,
  children: @[quitItem],
)
let menu = @[
  fileMenu
]

proc handleMenu(id: string) {.gcsafe.} =
  {.cast(gcsafe).}:
    menuIds.add id

let tray = TrayOptions(
  id: "main",
  tooltip: "Viewy",
  iconPath: "icon.png",
  templateIconPath: "icon-template.png",
  menu: @[MenuItem(id: "show", label: "Show", kind: miCommand, enabled: true)],
)

proc handleTray(id: string) {.gcsafe.} =
  {.cast(gcsafe).}:
    trayIds.add id

proc handleWindowEvent(event: WindowEvent) {.gcsafe.} =
  doAssert event.width == 640
  doAssert event.height == 480
  {.cast(gcsafe).}:
    windowEvents.add event.kind

when selectedBackend == "native":
  registerScheme(fakeBackend, h, "viewy", handleAsset)
  setAppMenu(fakeBackend, h, menu, handleMenu)
  trayCreate(fakeBackend, h, tray, handleTray)
  trayUpdate(fakeBackend, h, "main", tray)
  trayDestroy(fakeBackend, h, "main")
  onWindowEvent(fakeBackend, h, handleWindowEvent)

  var missingSchemeCapBackend = fakeBackend
  missingSchemeCapBackend.caps = {}
  var runtimeCapAsserted = false
  try:
    missingSchemeCapBackend.registerScheme(h, "viewy", handleAsset)
  except AssertionDefect:
    runtimeCapAsserted = true
  doAssert runtimeCapAsserted

  let incompleteTrayBackend = Backend(
    caps: {capTray},
    trayCreateImpl: fakeTrayCreate,
  )
  var incompleteTrayAsserted = false
  try:
    incompleteTrayBackend.trayCreate(h, tray, handleTray)
  except AssertionDefect:
    incompleteTrayAsserted = true
  doAssert incompleteTrayAsserted

doAssert capScheme in fakeBackend.caps
doAssert fakeBackend.dispatchTerminate != nil
doAssert fakeBackend.registerSchemeImpl != nil
doAssert fakeBackend.setAppMenuImpl != nil
doAssert fakeBackend.trayCreateImpl != nil
doAssert fakeBackend.trayUpdateImpl != nil
doAssert fakeBackend.trayDestroyImpl != nil
doAssert fakeBackend.onWindowEventImpl != nil
doAssert terminated
when selectedBackend == "native":
  doAssert schemeSeen == "viewy"
  doAssert assetPathSeen == "/index.html"
  doAssert menuIds == @["quit"]
  doAssert trayIds == @["main", "show", "main:updated", "main:destroyed"]
  doAssert windowEvents == @[weResize]

let liteBackend = newBackend()
doAssert liteBackend.caps == {}
doAssert liteBackend.dispatchTerminate != nil
doAssert liteBackend.registerSchemeImpl == nil
doAssert liteBackend.setAppMenuImpl == nil
doAssert liteBackend.trayCreateImpl == nil
doAssert liteBackend.trayUpdateImpl == nil
doAssert liteBackend.trayDestroyImpl == nil
doAssert liteBackend.onWindowEventImpl == nil

proc assertLiteCapGate(name, source, expected: string) =
  let probe = getTempDir() / ("viewy_cap_gate_" & name & ".nim")
  writeFile(probe, source)
  let (output, code) = execCmdEx(
    "nim check --path:src -d:viewyBackend=lite " & probe)
  removeFile(probe)
  doAssert code != 0
  doAssert output.contains(expected)

assertLiteCapGate("scheme_fail", """
import viewy/backend/api

proc handleAsset(request: AssetRequest): AssetResponse {.gcsafe.} =
  AssetResponse(status: 200, statusText: "OK", mimeType: "text/plain")

let backend = Backend(
  caps: {capScheme},
  registerSchemeImpl: proc(h: BackendHandle; scheme: string;
      handler: AssetHandler) = discard,
)

backend.registerScheme(nil, "viewy", handleAsset)
""", "registerScheme requires a backend capability")

assertLiteCapGate("menu_fail", """
import viewy/backend/api

let backend = Backend(
  caps: {capMenu},
  setAppMenuImpl: proc(h: BackendHandle; menu: seq[MenuItem];
      cb: MenuCallback) = discard,
)

backend.setAppMenu(nil, @[], proc(id: string) = discard)
""", "setAppMenu requires a backend capability")

assertLiteCapGate("tray_fail", """
import viewy/backend/api

let backend = Backend(
  caps: {capTray},
  trayCreateImpl: proc(h: BackendHandle; options: TrayOptions;
      cb: MenuCallback) = discard,
  trayUpdateImpl: proc(h: BackendHandle; id: string;
      options: TrayOptions) = discard,
  trayDestroyImpl: proc(h: BackendHandle; id: string) = discard,
)

backend.trayCreate(nil, TrayOptions(id: "main"), proc(id: string) = discard)
""", "trayCreate requires a backend capability")

echo "ok: backend v2 api types and slots"
