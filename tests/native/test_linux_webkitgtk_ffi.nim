when not defined(linux):
  echo "skipped linux webkitgtk ffi: non-linux host"
else:
  import viewy/backend/native/linux/webkitgtk_ffi

  proc schemeCb(request: ptr WebKitURISchemeRequest; data: pointer) {.cdecl,
      gcsafe.} =
    discard request
    discard data

  proc headerCb(name, value: cstring; userData: pointer) {.cdecl, gcsafe.} =
    discard name
    discard value
    discard userData

  doAssert ord(webkitLoadStarted) == 0
  doAssert ord(webkitUserScriptInjectAtDocumentStart) == 0
  doAssert ord(webkitUserContentInjectTopFrame) == 1

  when false:
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
    webkitWebViewEvaluateJavascript(webView, "void 0", -1, nil, nil, nil, nil, nil)
    webkitWebContextRegisterUriScheme(context, "viewy", schemeCb, nil, nil)
    discard webkitUriSchemeRequestGetScheme(request)
    discard webkitUriSchemeRequestGetUri(request)
    discard webkitUriSchemeRequestGetPath(request)
    discard webkitUriSchemeRequestGetHttpMethod(request)
    discard webkitUriSchemeRequestGetHttpHeaders(request)
    discard webkitUriSchemeRequestGetHttpBody(request)
    soupMessageHeadersForeach(webkitUriSchemeRequestGetHttpHeaders(request),
      headerCb, nil)
    webkitUriSchemeRequestFinish(request, nil, 0, "text/plain")
    webkitUriSchemeRequestFinishError(request, nil)
    discard webkitJavascriptResultGetGlobalContext(jsResult)
    discard webkitJavascriptResultGetJsValue(jsResult)
    webkitJavascriptResultUnref(jsResult)

  echo "ok: linux webkitgtk ffi declarations"
