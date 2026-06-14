when not defined(macosx):
  echo "skipped darwin native glue: non-macOS host"
else:
  const gluePath = "../../src/viewy/backend/native/darwin/glue.m"
  {.passL: "-framework Cocoa -framework WebKit".}
  {.compile: gluePath.}

  type
    ViewyDarwinApp {.importc: "ViewyDarwinApp",
        header: "../../src/viewy/backend/native/darwin/glue.h",
        incompleteStruct.} = object
    ViewyDarwinWindow {.importc: "ViewyDarwinWindow",
        header: "../../src/viewy/backend/native/darwin/glue.h",
        incompleteStruct.} = object

  proc viewyDarwinAppCreate(): ptr ViewyDarwinApp {.
      importc: "viewy_darwin_app_create",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinAppDestroy(app: ptr ViewyDarwinApp) {.
      importc: "viewy_darwin_app_destroy",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinWindowCreate(app: ptr ViewyDarwinApp;
      debug: int32): ptr ViewyDarwinWindow {.
      importc: "viewy_darwin_window_create",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinWindowDestroy(window: ptr ViewyDarwinWindow) {.
      importc: "viewy_darwin_window_destroy",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinSetMessageHandler(window: ptr ViewyDarwinWindow;
      handlerName: cstring; callback: pointer; userdata: pointer): int32 {.
      importc: "viewy_darwin_set_message_handler",
      header: "../../src/viewy/backend/native/darwin/glue.h".}
  proc viewyDarwinClearMessageHandler(window: ptr ViewyDarwinWindow;
      handlerName: cstring) {.
      importc: "viewy_darwin_clear_message_handler",
      header: "../../src/viewy/backend/native/darwin/glue.h".}

  doAssert declared(viewyDarwinAppCreate)
  doAssert declared(viewyDarwinAppDestroy)
  doAssert declared(viewyDarwinWindowCreate)
  doAssert declared(viewyDarwinWindowDestroy)
  doAssert declared(viewyDarwinSetMessageHandler)
  doAssert declared(viewyDarwinClearMessageHandler)

  echo "ok: darwin native glue declarations"
