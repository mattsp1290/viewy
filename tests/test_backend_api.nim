import viewy/backend/api
import viewy/backend/wv/backend

let fakeHandle = cast[BackendHandle](0x6)

var
  schemeSeen = ""
  assetPathSeen = ""
  menuIds: seq[string]
  trayIds: seq[string]
  windowEvents: seq[WindowEventKind]

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
  caps: {capScheme, capMenu, capTray, capWindowEvents},
  registerScheme: fakeRegisterScheme,
  setAppMenu: fakeSetAppMenu,
  trayCreate: fakeTrayCreate,
  trayUpdate: fakeTrayUpdate,
  trayDestroy: fakeTrayDestroy,
  onWindowEvent: fakeOnWindowEvent,
)

let h = fakeBackend.create(false)

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

fakeBackend.registerScheme(h, "viewy", handleAsset)

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

fakeBackend.setAppMenu(h, menu, handleMenu)

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

fakeBackend.trayCreate(h, tray, handleTray)
fakeBackend.trayUpdate(h, "main", tray)
fakeBackend.trayDestroy(h, "main")

proc handleWindowEvent(event: WindowEvent) {.gcsafe.} =
  doAssert event.width == 640
  doAssert event.height == 480
  {.cast(gcsafe).}:
    windowEvents.add event.kind

fakeBackend.onWindowEvent(h, handleWindowEvent)

doAssert capScheme in fakeBackend.caps
doAssert schemeSeen == "viewy"
doAssert assetPathSeen == "/index.html"
doAssert menuIds == @["quit"]
doAssert trayIds == @["main", "show", "main:updated", "main:destroyed"]
doAssert windowEvents == @[weResize]

let liteBackend = newBackend()
doAssert liteBackend.caps == {}
doAssert liteBackend.registerScheme == nil
doAssert liteBackend.setAppMenu == nil
doAssert liteBackend.trayCreate == nil
doAssert liteBackend.trayUpdate == nil
doAssert liteBackend.trayDestroy == nil
doAssert liteBackend.onWindowEvent == nil

echo "ok: backend v2 api types and slots"
