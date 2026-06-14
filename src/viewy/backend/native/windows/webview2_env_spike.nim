## Spike result for native Windows WebView2 environment creation.
##
## The pinned SDK exposes environment creation through WebView2Loader exports.
## A pure-Nim implementation that works with only the Evergreen runtime would
## need to reproduce that loader. The native backend therefore keeps one C++ TU
## for the loader path and uses hand-written Nim COM declarations after the
## environment is created.

import viewy/backend/windows_webview2_pin

type
  Hresult* = int32
  Pcwstr* = ptr UncheckedArray[uint16]

  CoreWebView2EnvironmentOptions* = object
  CoreWebView2Environment* = object

  CoreWebView2CreateEnvironmentCompletedHandler* = object
    lpVtbl*: ptr CoreWebView2CreateEnvironmentCompletedHandlerVtbl

  CreateEnvironmentQueryInterfaceProc* = proc(
    self: ptr CoreWebView2CreateEnvironmentCompletedHandler;
    riid: pointer;
    ppvObject: ptr pointer
  ): Hresult {.stdcall.}

  CreateEnvironmentAddRefProc* = proc(
    self: ptr CoreWebView2CreateEnvironmentCompletedHandler
  ): uint32 {.stdcall.}

  CreateEnvironmentReleaseProc* = proc(
    self: ptr CoreWebView2CreateEnvironmentCompletedHandler
  ): uint32 {.stdcall.}

  CreateEnvironmentInvokeProc* = proc(
    self: ptr CoreWebView2CreateEnvironmentCompletedHandler;
    errorCode: Hresult;
    result: ptr CoreWebView2Environment
  ): Hresult {.stdcall.}

  CoreWebView2CreateEnvironmentCompletedHandlerVtbl* = object
    queryInterface*: CreateEnvironmentQueryInterfaceProc
    addRef*: CreateEnvironmentAddRefProc
    release*: CreateEnvironmentReleaseProc
    invoke*: CreateEnvironmentInvokeProc

  CreateCoreWebView2EnvironmentWithOptionsProc* = proc(
    browserExecutableFolder: Pcwstr;
    userDataFolder: Pcwstr;
    environmentOptions: ptr CoreWebView2EnvironmentOptions;
    environmentCreatedHandler: ptr CoreWebView2CreateEnvironmentCompletedHandler
  ): Hresult {.stdcall.}

const
  webView2ComSpikeTimeboxDays* = 3
  webView2ComSpikeDecision* = "cpp-tu-fallback"
  webView2LoaderExportName* = "CreateCoreWebView2EnvironmentWithOptions"
  webView2LoaderDllName* = "WebView2Loader.dll"

  webView2NativeLoaderDefines* = [
    "WEBVIEW_EDGE=1",
    "WEBVIEW_MSWEBVIEW2_BUILTIN_IMPL=1",
    "WEBVIEW_MSWEBVIEW2_EXPLICIT_LINK=1",
  ]

  webView2NativeLoaderLibraries* = [
    "advapi32",
    "ole32",
    "shell32",
    "shlwapi",
    "user32",
    "version",
  ]

static:
  doAssert webView2SdkPackage == webView2ExpectedPackage
  doAssert webView2SdkVersion == webView2ExpectedVersion
