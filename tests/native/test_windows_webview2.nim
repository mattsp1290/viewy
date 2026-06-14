import std/unittest

import viewy/backend/native/windows/[com, webview2, win32]

var
  controllerAddRefs: int
  controllerCloses: int
  controllerReleases: int
  webviewReleases: int
  settingsReleases: int
  settingsCalls: seq[string]
  fakeWebView: ICoreWebView2
  fakeSettings: ICoreWebView2Settings

proc okControllerAddRef(self: ptr ICoreWebView2Controller): Ulong {.stdcall.} =
  discard self
  inc controllerAddRefs
  Ulong(2)

proc okControllerRelease(self: ptr ICoreWebView2Controller): Ulong {.stdcall.} =
  discard self
  inc controllerReleases
  Ulong(1)

proc okControllerClose(self: ptr ICoreWebView2Controller): Hresult {.stdcall.} =
  discard self
  inc controllerCloses
  sOk

proc okWebViewRelease(self: ptr ICoreWebView2): Ulong {.stdcall.} =
  discard self
  inc webviewReleases
  Ulong(1)

proc okSettingsRelease(self: ptr ICoreWebView2Settings): Ulong {.stdcall.} =
  discard self
  inc settingsReleases
  Ulong(1)

proc okPutParentWindow(self: ptr ICoreWebView2Controller;
    value: Hwnd): Hresult {.stdcall.} =
  discard self
  discard value
  sOk

proc okPutBounds(self: ptr ICoreWebView2Controller;
    value: Rect): Hresult {.stdcall.} =
  discard self
  discard value
  sOk

proc okGetCoreWebView2(self: ptr ICoreWebView2Controller;
    value: ptr ptr ICoreWebView2): Hresult {.stdcall.} =
  discard self
  value[] = addr fakeWebView
  sOk

proc nilGetCoreWebView2(self: ptr ICoreWebView2Controller;
    value: ptr ptr ICoreWebView2): Hresult {.stdcall.} =
  discard self
  value[] = nil
  sOk

proc okGetSettings(self: ptr ICoreWebView2;
    value: ptr ptr ICoreWebView2Settings): Hresult {.stdcall.} =
  discard self
  value[] = addr fakeSettings
  sOk

proc nilGetSettings(self: ptr ICoreWebView2;
    value: ptr ptr ICoreWebView2Settings): Hresult {.stdcall.} =
  discard self
  value[] = nil
  sOk

proc recordSetting(name: string; hr = sOk): Hresult =
  settingsCalls.add(name)
  hr

proc okPutScript(self: ptr ICoreWebView2Settings;
    value: Bool): Hresult {.stdcall.} =
  discard self
  discard value
  recordSetting("script")

proc okPutWebMessage(self: ptr ICoreWebView2Settings;
    value: Bool): Hresult {.stdcall.} =
  discard self
  discard value
  recordSetting("webMessage")

proc okPutDialogs(self: ptr ICoreWebView2Settings;
    value: Bool): Hresult {.stdcall.} =
  discard self
  discard value
  recordSetting("dialogs")

proc okPutStatusBar(self: ptr ICoreWebView2Settings;
    value: Bool): Hresult {.stdcall.} =
  discard self
  discard value
  recordSetting("statusBar")

proc okPutDevTools(self: ptr ICoreWebView2Settings;
    value: Bool): Hresult {.stdcall.} =
  discard self
  discard value
  recordSetting("devTools")

proc failPutDevTools(self: ptr ICoreWebView2Settings;
    value: Bool): Hresult {.stdcall.} =
  discard self
  discard value
  recordSetting("devTools", Hresult(-42))

proc okPutContextMenus(self: ptr ICoreWebView2Settings;
    value: Bool): Hresult {.stdcall.} =
  discard self
  discard value
  recordSetting("contextMenus")

proc okPutHostObjects(self: ptr ICoreWebView2Settings;
    value: Bool): Hresult {.stdcall.} =
  discard self
  discard value
  recordSetting("hostObjects")

proc okPutZoom(self: ptr ICoreWebView2Settings;
    value: Bool): Hresult {.stdcall.} =
  discard self
  discard value
  recordSetting("zoom")

proc okPutErrorPage(self: ptr ICoreWebView2Settings;
    value: Bool): Hresult {.stdcall.} =
  discard self
  discard value
  recordSetting("errorPage")

proc resetFakes() =
  controllerAddRefs = 0
  controllerCloses = 0
  controllerReleases = 0
  webviewReleases = 0
  settingsReleases = 0
  settingsCalls.setLen(0)

suite "windows webview2 wiring declarations":
  test "helpers classify HRESULT values":
    check succeeded(sOk)
    check failed(Hresult(-1))

  test "attachController adopts COM outputs only after success":
    resetFakes()
    var
      settingsVtbl = CoreWebView2SettingsVtbl(release: okSettingsRelease)
      webviewVtbl = CoreWebView2Vtbl(
        release: okWebViewRelease,
        getSettings: okGetSettings)
      controllerVtbl = CoreWebView2ControllerVtbl(
        addRef: okControllerAddRef,
        release: okControllerRelease,
        close: okControllerClose,
        putParentWindow: okPutParentWindow,
        putBounds: okPutBounds,
        getCoreWebView2: okGetCoreWebView2)
      controller = ICoreWebView2Controller(lpVtbl: addr controllerVtbl)
      handles: WebView2Handles
    fakeSettings = ICoreWebView2Settings(lpVtbl: addr settingsVtbl)
    fakeWebView = ICoreWebView2(lpVtbl: addr webviewVtbl)

    let hr = attachController(addr controller, nil, Rect(
      left: 0, top: 0, right: 800, bottom: 600), handles)

    check hr == sOk
    check handles.controller == addr controller
    check handles.webview == addr fakeWebView
    check handles.settings == addr fakeSettings
    check controllerAddRefs == 1
    check controllerReleases == 0
    check webviewReleases == 0
    check settingsReleases == 0

    releaseHandles(handles)
    check handles.controller == nil
    check handles.webview == nil
    check handles.settings == nil
    check controllerCloses == 1
    check controllerReleases == 1
    check webviewReleases == 1
    check settingsReleases == 1

  test "attachController rejects nil outputs and releases temporaries":
    resetFakes()
    block:
      var
        controllerVtbl = CoreWebView2ControllerVtbl(
          addRef: okControllerAddRef,
          release: okControllerRelease,
          putParentWindow: okPutParentWindow,
          putBounds: okPutBounds,
          getCoreWebView2: nilGetCoreWebView2)
        controller = ICoreWebView2Controller(lpVtbl: addr controllerVtbl)
        handles: WebView2Handles
      check attachController(addr controller, nil, Rect(), handles) ==
        Hresult(-2147467259)
      check handles.controller == nil
      check controllerAddRefs == 1
      check controllerReleases == 1

    resetFakes()
    block:
      var
        webviewVtbl = CoreWebView2Vtbl(
          release: okWebViewRelease,
          getSettings: nilGetSettings)
        controllerVtbl = CoreWebView2ControllerVtbl(
          addRef: okControllerAddRef,
          release: okControllerRelease,
          putParentWindow: okPutParentWindow,
          putBounds: okPutBounds,
          getCoreWebView2: okGetCoreWebView2)
        controller = ICoreWebView2Controller(lpVtbl: addr controllerVtbl)
        handles: WebView2Handles
      fakeWebView = ICoreWebView2(lpVtbl: addr webviewVtbl)
      check attachController(addr controller, nil, Rect(), handles) ==
        Hresult(-2147467259)
      check handles.webview == nil
      check controllerReleases == 1
      check webviewReleases == 1

  test "configureSettings stops on first failing setter":
    resetFakes()
    var
      settingsVtbl = CoreWebView2SettingsVtbl(
        putIsScriptEnabled: okPutScript,
        putIsWebMessageEnabled: okPutWebMessage,
        putAreDefaultScriptDialogsEnabled: okPutDialogs,
        putIsStatusBarEnabled: okPutStatusBar,
        putAreDevToolsEnabled: failPutDevTools,
        putAreDefaultContextMenusEnabled: okPutContextMenus,
        putAreHostObjectsAllowed: okPutHostObjects,
        putIsZoomControlEnabled: okPutZoom,
        putIsBuiltInErrorPageEnabled: okPutErrorPage)
      settings = ICoreWebView2Settings(lpVtbl: addr settingsVtbl)

    check configureSettings(addr settings) == Hresult(-42)
    check settingsCalls == @["script", "webMessage", "dialogs", "statusBar",
      "devTools"]

  test "configureSettings applies baseline settings in order":
    resetFakes()
    var
      settingsVtbl = CoreWebView2SettingsVtbl(
        putIsScriptEnabled: okPutScript,
        putIsWebMessageEnabled: okPutWebMessage,
        putAreDefaultScriptDialogsEnabled: okPutDialogs,
        putIsStatusBarEnabled: okPutStatusBar,
        putAreDevToolsEnabled: okPutDevTools,
        putAreDefaultContextMenusEnabled: okPutContextMenus,
        putAreHostObjectsAllowed: okPutHostObjects,
        putIsZoomControlEnabled: okPutZoom,
        putIsBuiltInErrorPageEnabled: okPutErrorPage)
      settings = ICoreWebView2Settings(lpVtbl: addr settingsVtbl)

    check configureSettings(addr settings, enableDevTools = true) == sOk
    check settingsCalls == @["script", "webMessage", "dialogs", "statusBar",
      "devTools", "contextMenus", "hostObjects", "zoom", "errorPage"]

when defined(windows) and defined(nimcheck):
  proc envCreated(
    self: ptr ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler;
    errorCode: Hresult;
    environment: ptr ICoreWebView2Environment
  ): Hresult {.stdcall.} =
    discard self
    discard errorCode
    discard environment
    sOk

  proc controllerCreated(
    self: ptr ICoreWebView2CreateCoreWebView2ControllerCompletedHandler;
    errorCode: Hresult;
    controller: ptr ICoreWebView2Controller
  ): Hresult {.stdcall.} =
    discard self
    discard errorCode
    discard controller
    sOk

  var
    envVtbl = CoreWebView2CreateEnvironmentCompletedHandlerVtbl(
      invoke: envCreated)
    envHandler = ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler(
      lpVtbl: addr envVtbl)
    controllerVtbl = CoreWebView2CreateControllerCompletedHandlerVtbl(
      invoke: controllerCreated)
    controllerHandler = ICoreWebView2CreateCoreWebView2ControllerCompletedHandler(
      lpVtbl: addr controllerVtbl)
    createEnvironment: CreateCoreWebView2EnvironmentWithOptionsProc
    environment: ptr ICoreWebView2Environment
    response: ptr ICoreWebView2WebResourceResponse

  discard startEnvironmentCreation(createEnvironment, nil, addr envHandler)
  discard createController(environment, nil, addr controllerHandler)
  discard createWebResourceResponse(environment, nil, 200, nil, nil,
    addr response)
