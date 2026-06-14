## WebView2 environment/controller/settings wiring for the native Windows backend.
##
## Environment creation uses the retained loader fallback recorded by the spike.
## Everything after the environment pointer crosses through hand-written COM
## declarations from `com.nim`.

import viewy/backend/native/windows/[com, win32]

type
  WebView2Handles* = object
    environment*: ptr ICoreWebView2Environment
    controller*: ptr ICoreWebView2Controller
    webview*: ptr ICoreWebView2
    settings*: ptr ICoreWebView2Settings

proc succeeded*(hr: Hresult): bool {.inline.} =
  hr >= 0

proc failed*(hr: Hresult): bool {.inline.} =
  hr < 0

proc startEnvironmentCreation*(createEnvironment:
    CreateCoreWebView2EnvironmentWithOptionsProc;
    userDataFolder: Pcwstr;
    handler: ptr ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler
): Hresult =
  if createEnvironment == nil or handler == nil:
    return Hresult(-2147024809) # E_INVALIDARG
  createEnvironment(nil, userDataFolder, nil, handler)

proc createController*(environment: ptr ICoreWebView2Environment;
    parentWindow: Hwnd;
    handler: ptr ICoreWebView2CreateCoreWebView2ControllerCompletedHandler
): Hresult =
  if environment == nil or environment.lpVtbl == nil or handler == nil:
    return Hresult(-2147024809)
  environment.lpVtbl.createCoreWebView2Controller(environment, parentWindow,
    handler)

proc createWebResourceResponse*(environment: ptr ICoreWebView2Environment;
    content: ptr IStream; statusCode: Int; reasonPhrase, headers: Pcwstr;
    response: ptr ptr ICoreWebView2WebResourceResponse): Hresult =
  if environment == nil or environment.lpVtbl == nil or response == nil:
    return Hresult(-2147024809)
  environment.lpVtbl.createWebResourceResponse(environment, content, statusCode,
    reasonPhrase, headers, response)

proc releaseController(controller: ptr ICoreWebView2Controller) =
  if controller != nil and controller.lpVtbl != nil:
    if controller.lpVtbl.close != nil:
      discard controller.lpVtbl.close(controller)
    discard controller.lpVtbl.release(controller)

proc releaseWebView(webview: ptr ICoreWebView2) =
  if webview != nil and webview.lpVtbl != nil:
    discard webview.lpVtbl.release(webview)

proc releaseSettings(settings: ptr ICoreWebView2Settings) =
  if settings != nil and settings.lpVtbl != nil:
    discard settings.lpVtbl.release(settings)

proc releaseEnvironment(environment: ptr ICoreWebView2Environment) =
  if environment != nil and environment.lpVtbl != nil:
    discard environment.lpVtbl.release(environment)

proc attachController*(controller: ptr ICoreWebView2Controller;
    parentWindow: Hwnd; bounds: Rect; handles: var WebView2Handles): Hresult =
  if controller == nil or controller.lpVtbl == nil:
    return Hresult(-2147024809)

  discard controller.lpVtbl.addRef(controller)

  var hr = controller.lpVtbl.putParentWindow(controller, parentWindow)
  if failed(hr):
    releaseController(controller)
    return hr

  hr = controller.lpVtbl.putBounds(controller, bounds)
  if failed(hr):
    releaseController(controller)
    return hr

  var webview: ptr ICoreWebView2
  hr = controller.lpVtbl.getCoreWebView2(controller, addr webview)
  if failed(hr):
    releaseController(controller)
    return hr

  if webview == nil or webview.lpVtbl == nil:
    releaseController(controller)
    return Hresult(-2147467259) # E_FAIL

  var settings: ptr ICoreWebView2Settings
  hr = webview.lpVtbl.getSettings(webview, addr settings)
  if failed(hr):
    releaseWebView(webview)
    releaseController(controller)
    return hr

  if settings == nil or settings.lpVtbl == nil:
    releaseWebView(webview)
    releaseController(controller)
    return Hresult(-2147467259)

  handles.controller = controller
  handles.webview = webview
  handles.settings = settings
  sOk

proc releaseHandles*(handles: var WebView2Handles) =
  releaseSettings(handles.settings)
  releaseWebView(handles.webview)
  releaseController(handles.controller)
  releaseEnvironment(handles.environment)
  handles = WebView2Handles()

proc configureSettings*(settings: ptr ICoreWebView2Settings;
    enableDevTools = false): Hresult =
  if settings == nil or settings.lpVtbl == nil:
    return Hresult(-2147024809)

  var hr = settings.lpVtbl.putIsScriptEnabled(settings, winTrue)
  if failed(hr):
    return hr
  hr = settings.lpVtbl.putIsWebMessageEnabled(settings, winTrue)
  if failed(hr):
    return hr
  hr = settings.lpVtbl.putAreDefaultScriptDialogsEnabled(settings, winTrue)
  if failed(hr):
    return hr
  hr = settings.lpVtbl.putIsStatusBarEnabled(settings, winFalse)
  if failed(hr):
    return hr
  hr = settings.lpVtbl.putAreDevToolsEnabled(settings,
    if enableDevTools: winTrue else: winFalse)
  if failed(hr):
    return hr
  hr = settings.lpVtbl.putAreDefaultContextMenusEnabled(settings, winFalse)
  if failed(hr):
    return hr
  hr = settings.lpVtbl.putAreHostObjectsAllowed(settings, winFalse)
  if failed(hr):
    return hr
  hr = settings.lpVtbl.putIsZoomControlEnabled(settings, winFalse)
  if failed(hr):
    return hr
  settings.lpVtbl.putIsBuiltInErrorPageEnabled(settings, winTrue)

proc configureAttachedSettings*(handles: WebView2Handles;
    enableDevTools = false): Hresult =
  configureSettings(handles.settings, enableDevTools)
