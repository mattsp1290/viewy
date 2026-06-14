when not defined(macosx):
  echo "skipped darwin native glue: non-macOS host"
else:
  const gluePath = "../../src/viewy/backend/native/darwin/glue.m"
  {.passL: "-framework Cocoa -framework WebKit".}
  {.compile(gluePath, "-fobjc-arc").}

  type
    ConstCString {.importc: "const char *", nodecl.} = distinct cstring
    ViewyDarwinApp {.importc: "ViewyDarwinApp",
        header: "../../src/viewy/backend/native/darwin/glue.h",
        incompleteStruct.} = object
    ViewyDarwinWindow {.importc: "ViewyDarwinWindow",
        header: "../../src/viewy/backend/native/darwin/glue.h",
        incompleteStruct.} = object
    ViewyDarwinMessageCallback = proc(userdata: pointer; name, id,
        jsonArgs: ConstCString) {.cdecl.}
    ViewyDarwinMenuCallback = proc(userdata: pointer;
        id: ConstCString) {.cdecl.}
    ViewyDarwinEventCallback = proc(userdata: pointer; kind, width,
        height: int32) {.cdecl.}
    ViewyDarwinDispatchCallback = proc(userdata: pointer) {.cdecl.}

  proc viewyDarwinAppCreate(): ptr ViewyDarwinApp {.
      importc: "viewy_darwin_app_create",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinAppDestroy(app: ptr ViewyDarwinApp) {.
      importc: "viewy_darwin_app_destroy",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinAppRun(app: ptr ViewyDarwinApp) {.
      importc: "viewy_darwin_app_run",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinAppStop(app: ptr ViewyDarwinApp) {.
      importc: "viewy_darwin_app_stop",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinAppDispatch(app: ptr ViewyDarwinApp;
      fn: ViewyDarwinDispatchCallback; userdata: pointer) {.
      importc: "viewy_darwin_app_dispatch",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinWindowCreate(app: ptr ViewyDarwinApp;
      debug: int32): ptr ViewyDarwinWindow {.
      importc: "viewy_darwin_window_create",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinWindowDestroy(window: ptr ViewyDarwinWindow) {.
      importc: "viewy_darwin_window_destroy",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinWindowSetTitle(window: ptr ViewyDarwinWindow;
      title: cstring) {.importc: "viewy_darwin_window_set_title",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinWindowSetSize(window: ptr ViewyDarwinWindow; width, height,
      hints: int32) {.importc: "viewy_darwin_window_set_size",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinWindowSetHtml(window: ptr ViewyDarwinWindow; html: cstring) {.
      importc: "viewy_darwin_window_set_html",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinWindowNavigate(window: ptr ViewyDarwinWindow; url: cstring) {.
      importc: "viewy_darwin_window_navigate",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinWindowEval(window: ptr ViewyDarwinWindow; js: cstring) {.
      importc: "viewy_darwin_window_eval",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinWindowInitScript(window: ptr ViewyDarwinWindow;
      js: cstring) {.importc: "viewy_darwin_window_init_script",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinWindowShow(window: ptr ViewyDarwinWindow) {.
      importc: "viewy_darwin_window_show",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinWindowHide(window: ptr ViewyDarwinWindow) {.
      importc: "viewy_darwin_window_hide",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinSetMessageHandler(window: ptr ViewyDarwinWindow;
      handlerName: cstring; callback: ViewyDarwinMessageCallback;
      userdata: pointer): int32 {.
      importc: "viewy_darwin_set_message_handler",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinClearMessageHandler(window: ptr ViewyDarwinWindow;
      handlerName: cstring) {.
      importc: "viewy_darwin_clear_message_handler",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinResolve(window: ptr ViewyDarwinWindow; id: cstring;
      ok: int32; jsonResult: cstring) {.importc: "viewy_darwin_resolve",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinSetEventCallback(window: ptr ViewyDarwinWindow;
      callback: ViewyDarwinEventCallback; userdata: pointer) {.
      importc: "viewy_darwin_set_event_callback",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinSetAppMenu(app: ptr ViewyDarwinApp; jsonMenu: cstring;
      callback: ViewyDarwinMenuCallback; userdata: pointer): int32 {.
      importc: "viewy_darwin_set_app_menu",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinTrayCreate(app: ptr ViewyDarwinApp; jsonOptions: cstring;
      callback: ViewyDarwinMenuCallback; userdata: pointer): int32 {.
      importc: "viewy_darwin_tray_create",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinTrayUpdate(app: ptr ViewyDarwinApp; id,
      jsonOptions: cstring) {.importc: "viewy_darwin_tray_update",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinTrayDestroy(app: ptr ViewyDarwinApp; id: cstring) {.
      importc: "viewy_darwin_tray_destroy",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinTestMenuItemAcceleratorFlags(app: ptr ViewyDarwinApp;
      id, keyEquivalent: cstring; modifierMask: int64): int32 {.
      importc: "viewy_darwin_test_menu_item_accelerator_flags",
      header: "../../src/viewy/backend/native/darwin/glue.h".}

  proc dispatchCallback(userdata: pointer) {.cdecl.} =
    discard userdata

  proc messageCallback(userdata: pointer; name, id,
      jsonArgs: ConstCString) {.cdecl.} =
    discard userdata
    discard name
    discard id
    discard jsonArgs

  proc menuCallback(userdata: pointer; id: ConstCString) {.cdecl.} =
    discard userdata
    discard id

  proc eventCallback(userdata: pointer; kind, width, height: int32) {.cdecl.} =
    discard userdata
    discard kind
    discard width
    discard height

  doAssert declared(viewyDarwinAppCreate)
  doAssert declared(viewyDarwinAppDestroy)
  doAssert declared(viewyDarwinAppRun)
  doAssert declared(viewyDarwinAppStop)
  doAssert declared(viewyDarwinAppDispatch)
  doAssert declared(viewyDarwinWindowCreate)
  doAssert declared(viewyDarwinWindowDestroy)
  doAssert declared(viewyDarwinWindowSetTitle)
  doAssert declared(viewyDarwinWindowSetSize)
  doAssert declared(viewyDarwinWindowSetHtml)
  doAssert declared(viewyDarwinWindowNavigate)
  doAssert declared(viewyDarwinWindowEval)
  doAssert declared(viewyDarwinWindowInitScript)
  doAssert declared(viewyDarwinSetMessageHandler)
  doAssert declared(viewyDarwinClearMessageHandler)
  doAssert declared(viewyDarwinResolve)
  doAssert declared(viewyDarwinWindowShow)
  doAssert declared(viewyDarwinWindowHide)
  doAssert declared(viewyDarwinSetEventCallback)
  doAssert declared(viewyDarwinSetAppMenu)
  doAssert declared(viewyDarwinTrayCreate)
  doAssert declared(viewyDarwinTrayUpdate)
  doAssert declared(viewyDarwinTrayDestroy)
  doAssert declared(viewyDarwinTestMenuItemAcceleratorFlags)

  viewyDarwinAppDestroy(nil)
  viewyDarwinAppStop(nil)
  viewyDarwinAppDispatch(nil, dispatchCallback, nil)
  viewyDarwinWindowDestroy(nil)
  viewyDarwinWindowSetTitle(nil, "title")
  viewyDarwinWindowSetSize(nil, 800, 600, 0)
  viewyDarwinWindowSetHtml(nil, "<html></html>")
  viewyDarwinWindowNavigate(nil, "about:blank")
  viewyDarwinWindowEval(nil, "void 0")
  viewyDarwinWindowInitScript(nil, "void 0")
  viewyDarwinWindowShow(nil)
  viewyDarwinWindowHide(nil)
  doAssert viewyDarwinSetMessageHandler(nil, "viewy", messageCallback, nil) == 0
  viewyDarwinClearMessageHandler(nil, "viewy")
  viewyDarwinResolve(nil, "1", 1, "true")
  viewyDarwinSetEventCallback(nil, eventCallback, nil)
  doAssert viewyDarwinSetAppMenu(nil, "[]", menuCallback, nil) == 0
  doAssert viewyDarwinTrayCreate(nil, "{}", menuCallback, nil) == 0
  viewyDarwinTrayUpdate(nil, "main", "{}")
  viewyDarwinTrayDestroy(nil, "main")
  doAssert viewyDarwinTestMenuItemAcceleratorFlags(nil, "quit", "q", 1) == 0

  const
    nsControl = 1'i64 shl 18
    nsShift = 1'i64 shl 17
    nsOption = 1'i64 shl 19
    nsCommand = 1'i64 shl 20
    nsF12 = "\uF70F"

  let app = viewyDarwinAppCreate()
  doAssert app != nil
  let jsonMenu = """
[
  {
    "id":"",
    "label":"App",
    "kind":"submenu",
    "enabled":true,
    "children":[
      {"id":"quit","label":"Quit","kind":"command","enabled":true,"keyEquivalent":"Q","modifierFlags":["super"]},
      {"id":"power","label":"Power","kind":"command","enabled":true,"keyEquivalent":"P","modifierFlags":["ctrl","shift","alt"]},
      {"id":"help","label":"Help","kind":"command","enabled":true,"keyEquivalent":"F12","modifierFlags":["super"]},
      {"id":"slash","label":"Slash","kind":"command","enabled":true,"keyEquivalent":"Slash","modifierFlags":["super"]}
    ]
  }
]
"""
  doAssert viewyDarwinSetAppMenu(app, jsonMenu.cstring, menuCallback, nil) == 1
  doAssert viewyDarwinTestMenuItemAcceleratorFlags(app, "quit", "q",
      nsCommand) == 7
  doAssert viewyDarwinTestMenuItemAcceleratorFlags(app, "power", "p",
      nsControl or nsShift or nsOption) == 7
  doAssert viewyDarwinTestMenuItemAcceleratorFlags(app, "help", nsF12,
      nsCommand) == 7
  doAssert viewyDarwinTestMenuItemAcceleratorFlags(app, "slash", "/",
      nsCommand) == 7
  viewyDarwinAppDestroy(app)

  echo "ok: darwin native glue declarations"
