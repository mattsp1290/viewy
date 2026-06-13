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
  registerScheme: fakeRegisterScheme,
  setAppMenu: fakeSetAppMenu,
  trayCreate: fakeTrayCreate,
  trayUpdate: fakeTrayUpdate,
  trayDestroy: fakeTrayDestroy,
  onWindowEvent: fakeOnWindowEvent,
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

registerScheme(fakeBackend, h, "viewy", handleAsset)

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

setAppMenu(fakeBackend, h, menu, handleMenu)

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

trayCreate(fakeBackend, h, tray, handleTray)
trayUpdate(fakeBackend, h, "main", tray)
trayDestroy(fakeBackend, h, "main")

proc handleWindowEvent(event: WindowEvent) {.gcsafe.} =
  doAssert event.width == 640
  doAssert event.height == 480
  {.cast(gcsafe).}:
    windowEvents.add event.kind

onWindowEvent(fakeBackend, h, handleWindowEvent)

var missingSchemeCapBackend = fakeBackend
missingSchemeCapBackend.caps = {}
var runtimeCapAsserted = false
try:
  registerScheme(missingSchemeCapBackend, h, "viewy", handleAsset)
except AssertionDefect:
  runtimeCapAsserted = true
doAssert runtimeCapAsserted

doAssert capScheme in fakeBackend.caps
doAssert fakeBackend.dispatchTerminate != nil
doAssert fakeBackend.registerScheme != nil
doAssert fakeBackend.setAppMenu != nil
doAssert fakeBackend.trayCreate != nil
doAssert fakeBackend.trayUpdate != nil
doAssert fakeBackend.trayDestroy != nil
doAssert fakeBackend.onWindowEvent != nil
doAssert terminated
doAssert schemeSeen == "viewy"
doAssert assetPathSeen == "/index.html"
doAssert menuIds == @["quit"]
doAssert trayIds == @["main", "show", "main:updated", "main:destroyed"]
doAssert windowEvents == @[weResize]

let liteBackend = newBackend()
doAssert liteBackend.caps == {}
doAssert liteBackend.dispatchTerminate != nil
doAssert liteBackend.registerScheme == nil
doAssert liteBackend.setAppMenu == nil
doAssert liteBackend.trayCreate == nil
doAssert liteBackend.trayUpdate == nil
doAssert liteBackend.trayDestroy == nil
doAssert liteBackend.onWindowEvent == nil

let capGateProbe = getTempDir() / "viewy_cap_gate_lite_fail.nim"
writeFile(capGateProbe, """
import viewy/backend/api

proc handleAsset(request: AssetRequest): AssetResponse {.gcsafe.} =
  AssetResponse(status: 200, statusText: "OK", mimeType: "text/plain")

let backend = Backend(
  caps: {capScheme},
  registerScheme: proc(h: BackendHandle; scheme: string;
      handler: AssetHandler) = discard,
)

registerScheme(backend, nil, "viewy", handleAsset)
""")
let (capGateOutput, capGateCode) = execCmdEx(
  "nim check --path:src -d:viewyBackend=lite " & capGateProbe)
removeFile(capGateProbe)
doAssert capGateCode != 0
doAssert capGateOutput.contains("registerScheme requires a backend capability")

echo "ok: backend v2 api types and slots"
