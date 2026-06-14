import viewy/backend/native/windows/webview2_env_spike

doAssert webView2ComSpikeTimeboxDays == 3
doAssert webView2ComSpikeDecision == "cpp-tu-fallback"
doAssert webView2LoaderExportName == "CreateCoreWebView2EnvironmentWithOptions"
doAssert webView2LoaderDllName == "WebView2Loader.dll"
doAssert "WEBVIEW_MSWEBVIEW2_BUILTIN_IMPL=1" in webView2NativeLoaderDefines
doAssert "WEBVIEW_MSWEBVIEW2_EXPLICIT_LINK=1" in webView2NativeLoaderDefines
doAssert "ole32" in webView2NativeLoaderLibraries

when defined(windows) and defined(nimcheck):
  proc environmentCreated(
    self: ptr CoreWebView2CreateEnvironmentCompletedHandler;
    errorCode: Hresult;
    environment: ptr CoreWebView2Environment
  ): Hresult {.stdcall.} =
    discard self
    discard errorCode
    discard environment
    0

  var
    vtbl = CoreWebView2CreateEnvironmentCompletedHandlerVtbl(
      invoke: environmentCreated)
    handler = CoreWebView2CreateEnvironmentCompletedHandler(lpVtbl: addr vtbl)
    createEnvironment: CreateCoreWebView2EnvironmentWithOptionsProc

  if createEnvironment != nil:
    discard createEnvironment(nil, nil, nil, addr handler)

echo "ok: Windows WebView2 environment spike chose ", webView2ComSpikeDecision
