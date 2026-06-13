when not defined(linux):
  echo "skipped linux webkitgtk ffi: non-linux host"
else:
  import std/os

  import viewy/backend/native/linux/webkitgtk_ffi

  proc schemeCb(request: ptr WebKitURISchemeRequest; data: pointer) {.cdecl,
      gcsafe.} =
    discard request
    discard data

  proc headerCb(name, value: cstring; userData: pointer) {.cdecl, gcsafe.} =
    discard name
    discard value
    discard userData

  proc evalCb(sourceObject: pointer; result: ptr GAsyncResult;
      userData: pointer) {.cdecl, gcsafe.} =
    discard sourceObject
    discard result
    discard userData

  doAssert ord(webkitLoadStarted) == 0
  doAssert ord(webkitUserScriptInjectAtDocumentStart) == 0
  doAssert ord(webkitUserContentInjectTopFrame) == 1

  if getEnv("VIEWY_FFI_EXERCISE") == "1":
    let
      manager = webkitUserContentManagerNew()
      script = webkitUserScriptNew("window.__viewy = {}",
        webkitUserContentInjectTopFrame,
        webkitUserScriptInjectAtDocumentStart, nil, nil)
      widget = webkitWebViewNewWithUserContentManager(manager)
      webView = cast[ptr WebKitWebView](widget)
      settings = webkitSettingsNew()
      context = webkitWebContextGetDefault()
      request = cast[ptr WebKitURISchemeRequest](nil)
      jsResult = cast[ptr WebKitJavascriptResult](nil)
      asyncResult = cast[ptr GAsyncResult](nil)
      bytes = gBytesNew(nil, 0)
      stream = gMemoryInputStreamNewFromBytes(bytes)
      headers = soupMessageHeadersNew(soupMessageHeadersResponse)
      response = webkitUriSchemeResponseNew(stream, 0)
    var error: ptr GError
    var buffer: array[16, byte]
    webkitUserContentManagerAddScript(manager, script)
    discard webkitUserContentManagerRegisterScriptMessageHandler(manager, "viewy")
    webkitUserContentManagerUnregisterScriptMessageHandler(manager, "viewy")
    webkitUserScriptUnref(script)
    webkitSettingsSetDeveloperExtrasEnabled(settings, gTrue)
    webkitSettingsSetEnableJavascript(settings, gTrue)
    webkitWebViewSetSettings(webView, settings)
    discard webkitWebViewGetSettings(webView)
    webkitWebViewLoadHtml(webView, "<html></html>", "viewy://app/")
    webkitWebViewLoadUri(webView, "viewy://app/index.html")
    webkitWebViewEvaluateJavascript(webView, "void 0", -1, nil, nil, nil,
      evalCb, nil)
    discard webkitWebViewEvaluateJavascriptFinish(webView, asyncResult, addr error)
    webkitWebContextRegisterUriScheme(context, "viewy", schemeCb, nil, nil)
    discard webkitUriSchemeRequestGetScheme(request)
    discard webkitUriSchemeRequestGetUri(request)
    discard webkitUriSchemeRequestGetPath(request)
    discard webkitUriSchemeRequestGetHttpMethod(request)
    discard webkitUriSchemeRequestGetHttpHeaders(request)
    discard webkitUriSchemeRequestGetHttpBody(request)
    discard gInputStreamRead(stream, addr buffer[0], buffer.len.GSize, nil,
      addr error)
    discard gInputStreamClose(stream, nil, addr error)
    soupMessageHeadersAppend(headers, "Cache-Control", "no-store")
    soupMessageHeadersForeach(webkitUriSchemeRequestGetHttpHeaders(request),
      headerCb, nil)
    webkitUriSchemeResponseSetContentType(response, "text/plain")
    webkitUriSchemeResponseSetStatus(response, 200, "OK")
    webkitUriSchemeResponseSetHttpHeaders(response, headers)
    webkitUriSchemeRequestFinish(request, stream, 0, "text/plain")
    webkitUriSchemeRequestFinishWithResponse(request, response)
    webkitUriSchemeRequestFinishError(request, nil)
    discard webkitJavascriptResultGetGlobalContext(jsResult)
    discard webkitJavascriptResultGetJsValue(jsResult)
    webkitJavascriptResultUnref(jsResult)
    soupMessageHeadersFree(headers)
    gBytesUnref(bytes)

  echo "ok: linux webkitgtk ffi declarations"
