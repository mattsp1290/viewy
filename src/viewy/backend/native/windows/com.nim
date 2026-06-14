## Minimal WebView2 COM declarations for the native Windows backend.
##
## Pinned to `vendor/webview2/PIN` through `windows_webview2_pin`. This module
## intentionally declares only the interfaces needed by the planned backend:
## CoreWebView2, Environment, Controller, Settings, WebResourceRequested
## request/response args, and callback interfaces.

import viewy/backend/native/windows/win32
import viewy/backend/windows_webview2_pin

type
  Hresult* = int32
  Ulong* = uint32
  Pcwstr* = Lpcwstr
  Pwwstr* = ptr Lpwstr
  EventRegistrationToken* = object
    value*: int64

  ComMethod* = pointer
  Iid* = object
    data1*: uint32
    data2*: uint16
    data3*: uint16
    data4*: array[8, uint8]
  Refiid* = ptr Iid

  IStream* = object
    lpVtbl*: ptr IStreamVtbl
  IUnknown* = object
  ICoreWebView2* = object
    lpVtbl*: ptr CoreWebView2Vtbl
  ICoreWebView2Environment* = object
    lpVtbl*: ptr CoreWebView2EnvironmentVtbl
  ICoreWebView2Controller* = object
    lpVtbl*: ptr CoreWebView2ControllerVtbl
  ICoreWebView2Settings* = object
    lpVtbl*: ptr CoreWebView2SettingsVtbl
  ICoreWebView2WebResourceRequest* = object
    lpVtbl*: ptr CoreWebView2WebResourceRequestVtbl
  ICoreWebView2WebResourceResponse* = object
    lpVtbl*: ptr CoreWebView2WebResourceResponseVtbl
  ICoreWebView2WebResourceRequestedEventArgs* = object
    lpVtbl*: ptr CoreWebView2WebResourceRequestedEventArgsVtbl
  ICoreWebView2Deferral* = object
  ICoreWebView2HttpHeadersCollectionIterator* = object
    lpVtbl*: ptr CoreWebView2HttpHeadersCollectionIteratorVtbl
  ICoreWebView2HttpRequestHeaders* = object
    lpVtbl*: ptr CoreWebView2HttpRequestHeadersVtbl
  ICoreWebView2HttpResponseHeaders* = object
  ICoreWebView2EnvironmentOptions* = object

  QueryInterfaceProc*[T] = proc(self: ptr T; riid: Refiid;
    ppvObject: ptr pointer): Hresult {.stdcall.}
  AddRefProc*[T] = proc(self: ptr T): Ulong {.stdcall.}
  ReleaseProc*[T] = proc(self: ptr T): Ulong {.stdcall.}

  IUnknownVtbl*[T] = object
    queryInterface*: QueryInterfaceProc[T]
    addRef*: AddRefProc[T]
    release*: ReleaseProc[T]

  WebResourceContext* {.size: sizeof(cint).} = enum
    wrcAll = 0
    wrcDocument = 1
    wrcStylesheet = 2
    wrcImage = 3
    wrcMedia = 4
    wrcFont = 5
    wrcScript = 6
    wrcXmlHttpRequest = 7
    wrcFetch = 8
    wrcTextTrack = 9
    wrcEventSource = 10
    wrcWebsocket = 11
    wrcManifest = 12
    wrcSignedExchange = 13
    wrcPing = 14
    wrcCspViolationReport = 15
    wrcOther = 16

  MoveFocusReason* {.size: sizeof(cint).} = enum
    mfrProgrammatic = 0
    mfrNext = 1
    mfrPrevious = 2

  IStreamVtbl* = object
    queryInterface*: QueryInterfaceProc[IStream]
    addRef*: AddRefProc[IStream]
    release*: ReleaseProc[IStream]
    read*: proc(self: ptr IStream; pv: pointer; cb: Ulong;
      pcbRead: ptr Ulong): Hresult {.stdcall.}
    write*: ComMethod

  CoreWebView2HttpHeadersCollectionIteratorVtbl* = object
    queryInterface*: QueryInterfaceProc[ICoreWebView2HttpHeadersCollectionIterator]
    addRef*: AddRefProc[ICoreWebView2HttpHeadersCollectionIterator]
    release*: ReleaseProc[ICoreWebView2HttpHeadersCollectionIterator]
    getCurrentHeader*: proc(
      self: ptr ICoreWebView2HttpHeadersCollectionIterator;
      name, value: Pwwstr): Hresult {.stdcall.}
    getHasCurrentHeader*: proc(
      self: ptr ICoreWebView2HttpHeadersCollectionIterator;
      hasCurrent: ptr Bool): Hresult {.stdcall.}
    moveNext*: proc(self: ptr ICoreWebView2HttpHeadersCollectionIterator;
      hasNext: ptr Bool): Hresult {.stdcall.}

  CoreWebView2HttpRequestHeadersVtbl* = object
    queryInterface*: QueryInterfaceProc[ICoreWebView2HttpRequestHeaders]
    addRef*: AddRefProc[ICoreWebView2HttpRequestHeaders]
    release*: ReleaseProc[ICoreWebView2HttpRequestHeaders]
    getHeader*: proc(self: ptr ICoreWebView2HttpRequestHeaders;
      name: Pcwstr; value: Pwwstr): Hresult {.stdcall.}
    getHeaders*: proc(self: ptr ICoreWebView2HttpRequestHeaders;
      name: Pcwstr;
      value: ptr ptr ICoreWebView2HttpHeadersCollectionIterator): Hresult {.stdcall.}
    contains*: proc(self: ptr ICoreWebView2HttpRequestHeaders;
      name: Pcwstr; value: ptr Bool): Hresult {.stdcall.}
    setHeader*: proc(self: ptr ICoreWebView2HttpRequestHeaders;
      name, value: Pcwstr): Hresult {.stdcall.}
    removeHeader*: proc(self: ptr ICoreWebView2HttpRequestHeaders;
      name: Pcwstr): Hresult {.stdcall.}
    getIterator*: proc(self: ptr ICoreWebView2HttpRequestHeaders;
      value: ptr ptr ICoreWebView2HttpHeadersCollectionIterator): Hresult {.stdcall.}

  CoreWebView2SettingsVtbl* = object
    queryInterface*: QueryInterfaceProc[ICoreWebView2Settings]
    addRef*: AddRefProc[ICoreWebView2Settings]
    release*: ReleaseProc[ICoreWebView2Settings]
    getIsScriptEnabled*: proc(self: ptr ICoreWebView2Settings;
      value: ptr Bool): Hresult {.stdcall.}
    putIsScriptEnabled*: proc(self: ptr ICoreWebView2Settings;
      value: Bool): Hresult {.stdcall.}
    getIsWebMessageEnabled*: proc(self: ptr ICoreWebView2Settings;
      value: ptr Bool): Hresult {.stdcall.}
    putIsWebMessageEnabled*: proc(self: ptr ICoreWebView2Settings;
      value: Bool): Hresult {.stdcall.}
    getAreDefaultScriptDialogsEnabled*: proc(self: ptr ICoreWebView2Settings;
      value: ptr Bool): Hresult {.stdcall.}
    putAreDefaultScriptDialogsEnabled*: proc(self: ptr ICoreWebView2Settings;
      value: Bool): Hresult {.stdcall.}
    getIsStatusBarEnabled*: proc(self: ptr ICoreWebView2Settings;
      value: ptr Bool): Hresult {.stdcall.}
    putIsStatusBarEnabled*: proc(self: ptr ICoreWebView2Settings;
      value: Bool): Hresult {.stdcall.}
    getAreDevToolsEnabled*: proc(self: ptr ICoreWebView2Settings;
      value: ptr Bool): Hresult {.stdcall.}
    putAreDevToolsEnabled*: proc(self: ptr ICoreWebView2Settings;
      value: Bool): Hresult {.stdcall.}
    getAreDefaultContextMenusEnabled*: proc(self: ptr ICoreWebView2Settings;
      value: ptr Bool): Hresult {.stdcall.}
    putAreDefaultContextMenusEnabled*: proc(self: ptr ICoreWebView2Settings;
      value: Bool): Hresult {.stdcall.}
    getAreHostObjectsAllowed*: proc(self: ptr ICoreWebView2Settings;
      value: ptr Bool): Hresult {.stdcall.}
    putAreHostObjectsAllowed*: proc(self: ptr ICoreWebView2Settings;
      value: Bool): Hresult {.stdcall.}
    getIsZoomControlEnabled*: proc(self: ptr ICoreWebView2Settings;
      value: ptr Bool): Hresult {.stdcall.}
    putIsZoomControlEnabled*: proc(self: ptr ICoreWebView2Settings;
      value: Bool): Hresult {.stdcall.}
    getIsBuiltInErrorPageEnabled*: proc(self: ptr ICoreWebView2Settings;
      value: ptr Bool): Hresult {.stdcall.}
    putIsBuiltInErrorPageEnabled*: proc(self: ptr ICoreWebView2Settings;
      value: Bool): Hresult {.stdcall.}

  CoreWebView2ControllerVtbl* = object
    queryInterface*: QueryInterfaceProc[ICoreWebView2Controller]
    addRef*: AddRefProc[ICoreWebView2Controller]
    release*: ReleaseProc[ICoreWebView2Controller]
    getIsVisible*: proc(self: ptr ICoreWebView2Controller;
      value: ptr Bool): Hresult {.stdcall.}
    putIsVisible*: proc(self: ptr ICoreWebView2Controller;
      value: Bool): Hresult {.stdcall.}
    getBounds*: proc(self: ptr ICoreWebView2Controller;
      value: ptr Rect): Hresult {.stdcall.}
    putBounds*: proc(self: ptr ICoreWebView2Controller;
      value: Rect): Hresult {.stdcall.}
    getZoomFactor*: ComMethod
    putZoomFactor*: ComMethod
    addZoomFactorChanged*: ComMethod
    removeZoomFactorChanged*: ComMethod
    setBoundsAndZoomFactor*: ComMethod
    moveFocus*: proc(self: ptr ICoreWebView2Controller;
      reason: MoveFocusReason): Hresult {.stdcall.}
    addMoveFocusRequested*: ComMethod
    removeMoveFocusRequested*: ComMethod
    addGotFocus*: ComMethod
    removeGotFocus*: ComMethod
    addLostFocus*: ComMethod
    removeLostFocus*: ComMethod
    addAcceleratorKeyPressed*: ComMethod
    removeAcceleratorKeyPressed*: ComMethod
    getParentWindow*: proc(self: ptr ICoreWebView2Controller;
      value: ptr Hwnd): Hresult {.stdcall.}
    putParentWindow*: proc(self: ptr ICoreWebView2Controller;
      value: Hwnd): Hresult {.stdcall.}
    notifyParentWindowPositionChanged*: proc(
      self: ptr ICoreWebView2Controller): Hresult {.stdcall.}
    close*: proc(self: ptr ICoreWebView2Controller): Hresult {.stdcall.}
    getCoreWebView2*: proc(self: ptr ICoreWebView2Controller;
      value: ptr ptr ICoreWebView2): Hresult {.stdcall.}

  CoreWebView2WebResourceRequestVtbl* = object
    queryInterface*: QueryInterfaceProc[ICoreWebView2WebResourceRequest]
    addRef*: AddRefProc[ICoreWebView2WebResourceRequest]
    release*: ReleaseProc[ICoreWebView2WebResourceRequest]
    getUri*: proc(self: ptr ICoreWebView2WebResourceRequest;
      value: Pwwstr): Hresult {.stdcall.}
    putUri*: proc(self: ptr ICoreWebView2WebResourceRequest;
      value: Pcwstr): Hresult {.stdcall.}
    getMethod*: proc(self: ptr ICoreWebView2WebResourceRequest;
      value: Pwwstr): Hresult {.stdcall.}
    putMethod*: proc(self: ptr ICoreWebView2WebResourceRequest;
      value: Pcwstr): Hresult {.stdcall.}
    getContent*: proc(self: ptr ICoreWebView2WebResourceRequest;
      value: ptr ptr IStream): Hresult {.stdcall.}
    putContent*: proc(self: ptr ICoreWebView2WebResourceRequest;
      value: ptr IStream): Hresult {.stdcall.}
    getHeaders*: proc(self: ptr ICoreWebView2WebResourceRequest;
      value: ptr ptr ICoreWebView2HttpRequestHeaders): Hresult {.stdcall.}

  CoreWebView2WebResourceResponseVtbl* = object
    queryInterface*: QueryInterfaceProc[ICoreWebView2WebResourceResponse]
    addRef*: AddRefProc[ICoreWebView2WebResourceResponse]
    release*: ReleaseProc[ICoreWebView2WebResourceResponse]
    getContent*: proc(self: ptr ICoreWebView2WebResourceResponse;
      value: ptr ptr IStream): Hresult {.stdcall.}
    putContent*: proc(self: ptr ICoreWebView2WebResourceResponse;
      value: ptr IStream): Hresult {.stdcall.}
    getHeaders*: proc(self: ptr ICoreWebView2WebResourceResponse;
      value: ptr ptr ICoreWebView2HttpResponseHeaders): Hresult {.stdcall.}
    getStatusCode*: proc(self: ptr ICoreWebView2WebResourceResponse;
      value: ptr Int): Hresult {.stdcall.}
    putStatusCode*: proc(self: ptr ICoreWebView2WebResourceResponse;
      value: Int): Hresult {.stdcall.}
    getReasonPhrase*: proc(self: ptr ICoreWebView2WebResourceResponse;
      value: Pwwstr): Hresult {.stdcall.}
    putReasonPhrase*: proc(self: ptr ICoreWebView2WebResourceResponse;
      value: Pcwstr): Hresult {.stdcall.}

  CoreWebView2WebResourceRequestedEventArgsVtbl* = object
    queryInterface*: QueryInterfaceProc[ICoreWebView2WebResourceRequestedEventArgs]
    addRef*: AddRefProc[ICoreWebView2WebResourceRequestedEventArgs]
    release*: ReleaseProc[ICoreWebView2WebResourceRequestedEventArgs]
    getRequest*: proc(self: ptr ICoreWebView2WebResourceRequestedEventArgs;
      value: ptr ptr ICoreWebView2WebResourceRequest): Hresult {.stdcall.}
    getResponse*: proc(self: ptr ICoreWebView2WebResourceRequestedEventArgs;
      value: ptr ptr ICoreWebView2WebResourceResponse): Hresult {.stdcall.}
    putResponse*: proc(self: ptr ICoreWebView2WebResourceRequestedEventArgs;
      value: ptr ICoreWebView2WebResourceResponse): Hresult {.stdcall.}
    getDeferral*: proc(self: ptr ICoreWebView2WebResourceRequestedEventArgs;
      value: ptr ptr ICoreWebView2Deferral): Hresult {.stdcall.}
    getResourceContext*: proc(self: ptr ICoreWebView2WebResourceRequestedEventArgs;
      value: ptr WebResourceContext): Hresult {.stdcall.}

  CoreWebView2EnvironmentVtbl* = object
    queryInterface*: QueryInterfaceProc[ICoreWebView2Environment]
    addRef*: AddRefProc[ICoreWebView2Environment]
    release*: ReleaseProc[ICoreWebView2Environment]
    createCoreWebView2Controller*: proc(self: ptr ICoreWebView2Environment;
      parentWindow: Hwnd;
      handler: ptr ICoreWebView2CreateCoreWebView2ControllerCompletedHandler
    ): Hresult {.stdcall.}
    createWebResourceResponse*: proc(self: ptr ICoreWebView2Environment;
      content: ptr IStream; statusCode: Int; reasonPhrase: Pcwstr;
      headers: Pcwstr; response: ptr ptr ICoreWebView2WebResourceResponse
    ): Hresult {.stdcall.}
    getBrowserVersionString*: proc(self: ptr ICoreWebView2Environment;
      value: Pwwstr): Hresult {.stdcall.}
    addNewBrowserVersionAvailable*: ComMethod
    removeNewBrowserVersionAvailable*: ComMethod

  CoreWebView2Vtbl* = object
    queryInterface*: QueryInterfaceProc[ICoreWebView2]
    addRef*: AddRefProc[ICoreWebView2]
    release*: ReleaseProc[ICoreWebView2]
    getSettings*: proc(self: ptr ICoreWebView2;
      settings: ptr ptr ICoreWebView2Settings): Hresult {.stdcall.}
    getSource*: proc(self: ptr ICoreWebView2; uri: Pwwstr): Hresult {.stdcall.}
    navigate*: proc(self: ptr ICoreWebView2; uri: Pcwstr): Hresult {.stdcall.}
    navigateToString*: proc(self: ptr ICoreWebView2;
      htmlContent: Pcwstr): Hresult {.stdcall.}
    addNavigationStarting*: ComMethod
    removeNavigationStarting*: ComMethod
    addContentLoading*: ComMethod
    removeContentLoading*: ComMethod
    addSourceChanged*: ComMethod
    removeSourceChanged*: ComMethod
    addHistoryChanged*: ComMethod
    removeHistoryChanged*: ComMethod
    addNavigationCompleted*: ComMethod
    removeNavigationCompleted*: ComMethod
    addFrameNavigationStarting*: ComMethod
    removeFrameNavigationStarting*: ComMethod
    addFrameNavigationCompleted*: ComMethod
    removeFrameNavigationCompleted*: ComMethod
    addScriptDialogOpening*: ComMethod
    removeScriptDialogOpening*: ComMethod
    addPermissionRequested*: proc(self: ptr ICoreWebView2;
      handler: ptr ICoreWebView2PermissionRequestedEventHandler;
      token: ptr EventRegistrationToken): Hresult {.stdcall.}
    removePermissionRequested*: proc(self: ptr ICoreWebView2;
      token: EventRegistrationToken): Hresult {.stdcall.}
    addProcessFailed*: ComMethod
    removeProcessFailed*: ComMethod
    addScriptToExecuteOnDocumentCreated*: proc(self: ptr ICoreWebView2;
      javaScript: Pcwstr;
      handler: ptr ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler
    ): Hresult {.stdcall.}
    removeScriptToExecuteOnDocumentCreated*: proc(self: ptr ICoreWebView2;
      id: Pcwstr): Hresult {.stdcall.}
    executeScript*: proc(self: ptr ICoreWebView2; javaScript: Pcwstr;
      handler: ptr ICoreWebView2ExecuteScriptCompletedHandler
    ): Hresult {.stdcall.}
    capturePreview*: ComMethod
    reload*: proc(self: ptr ICoreWebView2): Hresult {.stdcall.}
    postWebMessageAsJson*: proc(self: ptr ICoreWebView2;
      webMessageAsJson: Pcwstr): Hresult {.stdcall.}
    postWebMessageAsString*: proc(self: ptr ICoreWebView2;
      webMessageAsString: Pcwstr): Hresult {.stdcall.}
    addWebMessageReceived*: proc(self: ptr ICoreWebView2;
      handler: ptr ICoreWebView2WebMessageReceivedEventHandler;
      token: ptr EventRegistrationToken): Hresult {.stdcall.}
    removeWebMessageReceived*: proc(self: ptr ICoreWebView2;
      token: EventRegistrationToken): Hresult {.stdcall.}
    callDevToolsProtocolMethod*: ComMethod
    getBrowserProcessId*: ComMethod
    getCanGoBack*: ComMethod
    getCanGoForward*: ComMethod
    goBack*: ComMethod
    goForward*: ComMethod
    getDevToolsProtocolEventReceiver*: ComMethod
    stop*: ComMethod
    addNewWindowRequested*: ComMethod
    removeNewWindowRequested*: ComMethod
    addDocumentTitleChanged*: ComMethod
    removeDocumentTitleChanged*: ComMethod
    getDocumentTitle*: proc(self: ptr ICoreWebView2;
      title: Pwwstr): Hresult {.stdcall.}
    addHostObjectToScript*: ComMethod
    removeHostObjectFromScript*: ComMethod
    openDevToolsWindow*: ComMethod
    addContainsFullScreenElementChanged*: ComMethod
    removeContainsFullScreenElementChanged*: ComMethod
    getContainsFullScreenElement*: ComMethod
    addWebResourceRequested*: proc(self: ptr ICoreWebView2;
      handler: ptr ICoreWebView2WebResourceRequestedEventHandler;
      token: ptr EventRegistrationToken): Hresult {.stdcall.}
    removeWebResourceRequested*: proc(self: ptr ICoreWebView2;
      token: EventRegistrationToken): Hresult {.stdcall.}
    addWebResourceRequestedFilter*: proc(self: ptr ICoreWebView2;
      uri: Pcwstr; resourceContext: WebResourceContext): Hresult {.stdcall.}
    removeWebResourceRequestedFilter*: proc(self: ptr ICoreWebView2;
      uri: Pcwstr; resourceContext: WebResourceContext): Hresult {.stdcall.}
    addWindowCloseRequested*: ComMethod
    removeWindowCloseRequested*: ComMethod

  ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler* = object
    lpVtbl*: ptr CoreWebView2CreateEnvironmentCompletedHandlerVtbl
  ICoreWebView2CreateCoreWebView2ControllerCompletedHandler* = object
    lpVtbl*: ptr CoreWebView2CreateControllerCompletedHandlerVtbl
  ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler* = object
    lpVtbl*: ptr CoreWebView2AddScriptCompletedHandlerVtbl
  ICoreWebView2ExecuteScriptCompletedHandler* = object
    lpVtbl*: ptr CoreWebView2ExecuteScriptCompletedHandlerVtbl
  ICoreWebView2WebMessageReceivedEventHandler* = object
    lpVtbl*: ptr CoreWebView2WebMessageReceivedEventHandlerVtbl
  ICoreWebView2WebResourceRequestedEventHandler* = object
    lpVtbl*: ptr CoreWebView2WebResourceRequestedEventHandlerVtbl
  ICoreWebView2PermissionRequestedEventHandler* = object
    lpVtbl*: ptr CoreWebView2PermissionRequestedEventHandlerVtbl

  CoreWebView2CreateEnvironmentCompletedHandlerVtbl* = object
    queryInterface*: QueryInterfaceProc[ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler]
    addRef*: AddRefProc[ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler]
    release*: ReleaseProc[ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler]
    invoke*: proc(self: ptr ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler;
      errorCode: Hresult; result: ptr ICoreWebView2Environment
    ): Hresult {.stdcall.}

  CoreWebView2CreateControllerCompletedHandlerVtbl* = object
    queryInterface*: QueryInterfaceProc[ICoreWebView2CreateCoreWebView2ControllerCompletedHandler]
    addRef*: AddRefProc[ICoreWebView2CreateCoreWebView2ControllerCompletedHandler]
    release*: ReleaseProc[ICoreWebView2CreateCoreWebView2ControllerCompletedHandler]
    invoke*: proc(self: ptr ICoreWebView2CreateCoreWebView2ControllerCompletedHandler;
      errorCode: Hresult; result: ptr ICoreWebView2Controller
    ): Hresult {.stdcall.}

  CoreWebView2AddScriptCompletedHandlerVtbl* = object
    queryInterface*: QueryInterfaceProc[ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler]
    addRef*: AddRefProc[ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler]
    release*: ReleaseProc[ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler]
    invoke*: proc(self: ptr ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler;
      errorCode: Hresult; id: Pcwstr): Hresult {.stdcall.}

  CoreWebView2ExecuteScriptCompletedHandlerVtbl* = object
    queryInterface*: QueryInterfaceProc[ICoreWebView2ExecuteScriptCompletedHandler]
    addRef*: AddRefProc[ICoreWebView2ExecuteScriptCompletedHandler]
    release*: ReleaseProc[ICoreWebView2ExecuteScriptCompletedHandler]
    invoke*: proc(self: ptr ICoreWebView2ExecuteScriptCompletedHandler;
      errorCode: Hresult; resultObjectAsJson: Pcwstr): Hresult {.stdcall.}

  CoreWebView2WebMessageReceivedEventHandlerVtbl* = object
    queryInterface*: QueryInterfaceProc[ICoreWebView2WebMessageReceivedEventHandler]
    addRef*: AddRefProc[ICoreWebView2WebMessageReceivedEventHandler]
    release*: ReleaseProc[ICoreWebView2WebMessageReceivedEventHandler]
    invoke*: proc(self: ptr ICoreWebView2WebMessageReceivedEventHandler;
      sender: ptr ICoreWebView2; args: pointer): Hresult {.stdcall.}

  CoreWebView2WebResourceRequestedEventHandlerVtbl* = object
    queryInterface*: QueryInterfaceProc[ICoreWebView2WebResourceRequestedEventHandler]
    addRef*: AddRefProc[ICoreWebView2WebResourceRequestedEventHandler]
    release*: ReleaseProc[ICoreWebView2WebResourceRequestedEventHandler]
    invoke*: proc(self: ptr ICoreWebView2WebResourceRequestedEventHandler;
      sender: ptr ICoreWebView2; args: ptr ICoreWebView2WebResourceRequestedEventArgs
    ): Hresult {.stdcall.}

  CoreWebView2PermissionRequestedEventHandlerVtbl* = object
    queryInterface*: QueryInterfaceProc[ICoreWebView2PermissionRequestedEventHandler]
    addRef*: AddRefProc[ICoreWebView2PermissionRequestedEventHandler]
    release*: ReleaseProc[ICoreWebView2PermissionRequestedEventHandler]
    invoke*: proc(self: ptr ICoreWebView2PermissionRequestedEventHandler;
      sender: ptr ICoreWebView2; args: pointer): Hresult {.stdcall.}

  CreateCoreWebView2EnvironmentWithOptionsProc* = proc(
    browserExecutableFolder: Pcwstr;
    userDataFolder: Pcwstr;
    environmentOptions: ptr ICoreWebView2EnvironmentOptions;
    environmentCreatedHandler: ptr ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler
  ): Hresult {.stdcall.}

const
  sOk* = Hresult(0)
  eNoInterface* = Hresult(-2147467262)
  iidIUnknown* = Iid(
    data1: 0x00000000'u32, data2: 0x0000'u16, data3: 0x0000'u16,
    data4: [0xc0'u8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46])
  iidICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler* = Iid(
    data1: 0x4e8a3389'u32, data2: 0xc9d8'u16, data3: 0x4bd2'u16,
    data4: [0xb6'u8, 0xb5, 0x12, 0x4f, 0xee, 0x6c, 0xc1, 0x4d])
  iidICoreWebView2CreateCoreWebView2ControllerCompletedHandler* = Iid(
    data1: 0x6c4819f3'u32, data2: 0xc9b7'u16, data3: 0x4260'u16,
    data4: [0x81'u8, 0x27, 0xc9, 0xf5, 0xbd, 0xe7, 0xf6, 0x8c])
  iidICoreWebView2WebResourceRequestedEventHandler* = Iid(
    data1: 0xab00b74c'u32, data2: 0x15f1'u16, data3: 0x4646'u16,
    data4: [0x80'u8, 0xe8, 0xe7, 0x63, 0x41, 0xd2, 0x5d, 0x71])

static:
  doAssert webView2SdkPackage == webView2ExpectedPackage
  doAssert webView2SdkVersion == webView2ExpectedVersion
  doAssert sizeof(Hresult) == 4
  doAssert sizeof(Bool) == 4
  doAssert sizeof(Ulong) == 4
  doAssert sizeof(WebResourceContext) == sizeof(cint)
  doAssert sizeof(MoveFocusReason) == sizeof(cint)
  doAssert sizeof(EventRegistrationToken) == 8
  doAssert sizeof(IStreamVtbl) == sizeof(pointer) * 5
  doAssert sizeof(CoreWebView2HttpHeadersCollectionIteratorVtbl) ==
    sizeof(pointer) * 6
  doAssert sizeof(CoreWebView2HttpRequestHeadersVtbl) == sizeof(pointer) * 9
  doAssert sizeof(CoreWebView2EnvironmentVtbl) == sizeof(pointer) * 8
  doAssert sizeof(CoreWebView2ControllerVtbl) == sizeof(pointer) * 26
  doAssert sizeof(CoreWebView2SettingsVtbl) == sizeof(pointer) * 21
  doAssert sizeof(CoreWebView2WebResourceRequestVtbl) == sizeof(pointer) * 10
  doAssert sizeof(CoreWebView2WebResourceRequestedEventArgsVtbl) ==
    sizeof(pointer) * 8
  doAssert sizeof(CoreWebView2WebResourceResponseVtbl) == sizeof(pointer) * 10
  doAssert sizeof(CoreWebView2Vtbl) == sizeof(pointer) * 61
