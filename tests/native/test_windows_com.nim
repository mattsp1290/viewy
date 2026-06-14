when not defined(windows):
  echo "skipped windows com ffi: non-Windows host"
else:
  import viewy/backend/native/windows/com
  import viewy/backend/native/windows/win32

  doAssert sOk == 0
  doAssert eNoInterface == Hresult(-2147467262)
  doAssert sizeof(WebResourceContext) == sizeof(cint)
  doAssert sizeof(MoveFocusReason) == sizeof(cint)
  doAssert sizeof(EventRegistrationToken) == 8
  doAssert sizeof(CoreWebView2Vtbl) == sizeof(pointer) * 61
  doAssert sizeof(CoreWebView2EnvironmentVtbl) == sizeof(pointer) * 8
  doAssert sizeof(CoreWebView2ControllerVtbl) == sizeof(pointer) * 26
  doAssert sizeof(CoreWebView2SettingsVtbl) == sizeof(pointer) * 21
  doAssert sizeof(CoreWebView2WebResourceRequestedEventArgsVtbl) ==
    sizeof(pointer) * 8
  doAssert ord(wrcDocument) == 1
  doAssert ord(wrcFetch) == 8

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

  proc resourceRequested(
    self: ptr ICoreWebView2WebResourceRequestedEventHandler;
    sender: ptr ICoreWebView2;
    args: ptr ICoreWebView2WebResourceRequestedEventArgs
  ): Hresult {.stdcall.} =
    discard self
    discard sender
    discard args
    sOk

  when defined(nimcheck):
    var
      envVtbl = CoreWebView2CreateEnvironmentCompletedHandlerVtbl(
        invoke: envCreated)
      envHandler = ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler(
        lpVtbl: addr envVtbl)
      controllerVtbl = CoreWebView2CreateControllerCompletedHandlerVtbl(
        invoke: controllerCreated)
      controllerHandler = ICoreWebView2CreateCoreWebView2ControllerCompletedHandler(
        lpVtbl: addr controllerVtbl)
      resourceVtbl = CoreWebView2WebResourceRequestedEventHandlerVtbl(
        invoke: resourceRequested)
      resourceHandler = ICoreWebView2WebResourceRequestedEventHandler(
        lpVtbl: addr resourceVtbl)
      createEnvironment: CreateCoreWebView2EnvironmentWithOptionsProc
      token: EventRegistrationToken
      webview: ptr ICoreWebView2
      environment: ptr ICoreWebView2Environment
      controller: ptr ICoreWebView2Controller
      settings: ptr ICoreWebView2Settings
      request: ptr ICoreWebView2WebResourceRequest
      response: ptr ICoreWebView2WebResourceResponse
      args: ptr ICoreWebView2WebResourceRequestedEventArgs

    if createEnvironment != nil:
      discard createEnvironment(nil, nil, nil, addr envHandler)
    if environment != nil:
      discard environment.lpVtbl.createCoreWebView2Controller(environment, nil,
        addr controllerHandler)
      discard environment.lpVtbl.createWebResourceResponse(environment, nil,
        200, nil, nil, addr response)
    if controller != nil:
      discard controller.lpVtbl.putBounds(controller, Rect(
        left: 0, top: 0, right: 800, bottom: 600))
      discard controller.lpVtbl.getCoreWebView2(controller, addr webview)
      discard controller.lpVtbl.close(controller)
    if webview != nil:
      discard webview.lpVtbl.getSettings(webview, addr settings)
      discard webview.lpVtbl.navigate(webview, nil)
      discard webview.lpVtbl.navigateToString(webview, nil)
      discard webview.lpVtbl.addWebResourceRequested(webview,
        addr resourceHandler, addr token)
      discard webview.lpVtbl.addWebResourceRequestedFilter(webview, nil,
        wrcDocument)
    if settings != nil:
      discard settings.lpVtbl.putAreDevToolsEnabled(settings, winFalse)
      discard settings.lpVtbl.putIsWebMessageEnabled(settings, winTrue)
    if args != nil:
      discard args.lpVtbl.getRequest(args, addr request)
      discard args.lpVtbl.putResponse(args, response)
    if request != nil:
      discard request.lpVtbl.getUri(request, nil)
      discard request.lpVtbl.getMethod(request, nil)

  echo "ok: windows webview2 com declarations"
