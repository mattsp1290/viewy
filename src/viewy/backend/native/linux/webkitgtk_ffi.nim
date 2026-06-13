## Hand-written WebKitGTK 4.1 FFI surface for the native Linux backend.
##
## This module targets GTK3 + webkit2gtk-4.1. GTK4/webkitgtk-6.0 is a distinct
## future backend, not a flag of this one.

import ./gtk_ffi

when defined(linux) and not defined(nimcheck):
  import std/strutils

  proc pkgConfig(package: string): tuple[ok: bool; cflags,
      libs: string] {.compileTime.} =
    let cflags = gorge("pkg-config --cflags " & package).strip()
    if cflags.len == 0:
      return (false, "", "")
    let libs = gorge("pkg-config --libs " & package).strip()
    if libs.len == 0:
      return (false, "", "")
    (true, cflags, libs)

  proc versionAtLeast(package: string; major,
      minor: int): bool {.compileTime.} =
    gorge("pkg-config --atleast-version=" & $major & "." & $minor & " " &
        package).strip().len == 0

  const webkit = pkgConfig("gtk+-3.0 webkit2gtk-4.1")
  when not webkit.ok:
    {.error: "install libwebkit2gtk-4.1-dev and libgtk-3-dev for viewy native Linux backend".}
  when not versionAtLeast("webkit2gtk-4.1", 2, 40):
    {.error: "viewy native Linux backend requires webkit2gtk-4.1 >= 2.40".}

  {.passC: webkit.cflags.}
  {.passL: webkit.libs.}

type
  JSCContext* {.importc: "JSCContext", header: "jsc/jsc.h",
      incompleteStruct.} = object
  JSCValue* {.importc: "JSCValue", header: "jsc/jsc.h",
      incompleteStruct.} = object
  SoupMessageHeaders* {.importc: "SoupMessageHeaders", header: "libsoup/soup.h",
      incompleteStruct.} = object
  WebKitJavascriptResult* {.importc: "WebKitJavascriptResult",
      header: "webkit2/webkit2.h", incompleteStruct.} = object
  WebKitLoadEvent* {.size: sizeof(cint).} = enum
    webkitLoadStarted = 0
    webkitLoadRedirected = 1
    webkitLoadCommitted = 2
    webkitLoadFinished = 3
  WebKitSettings* {.importc: "WebKitSettings", header: "webkit2/webkit2.h",
      incompleteStruct.} = object
  WebKitURISchemeRequest* {.importc: "WebKitURISchemeRequest",
      header: "webkit2/webkit2.h", incompleteStruct.} = object
  WebKitURISchemeRequestCallback* = proc(request: ptr WebKitURISchemeRequest;
      data: pointer) {.cdecl, gcsafe.}
  WebKitUserContentInjectedFrames* {.size: sizeof(cint).} = enum
    webkitUserContentInjectAllFrames = 0
    webkitUserContentInjectTopFrame = 1
  WebKitUserContentManager* {.importc: "WebKitUserContentManager",
      header: "webkit2/webkit2.h", incompleteStruct.} = object
  WebKitUserScript* {.importc: "WebKitUserScript", header: "webkit2/webkit2.h",
      incompleteStruct.} = object
  WebKitUserScriptInjectionTime* {.size: sizeof(cint).} = enum
    webkitUserScriptInjectAtDocumentStart = 0
    webkitUserScriptInjectAtDocumentEnd = 1
  WebKitWebContext* {.importc: "WebKitWebContext", header: "webkit2/webkit2.h",
      incompleteStruct.} = object
  WebKitWebView* {.importc: "WebKitWebView", header: "webkit2/webkit2.h",
      incompleteStruct.} = object
  WebKitWebViewBase* {.importc: "WebKitWebViewBase",
      header: "webkit2/webkit2.h", incompleteStruct.} = object

proc jscValueToString*(value: ptr JSCValue): cstring
  {.importc: "jsc_value_to_string", header: "jsc/jsc.h", cdecl.}

proc soupMessageHeadersForeach*(headers: ptr SoupMessageHeaders; callback: proc(
    name, value: cstring; userData: pointer) {.cdecl, gcsafe.};
    userData: pointer)
  {.importc: "soup_message_headers_foreach", header: "libsoup/soup.h", cdecl.}

proc webkitJavascriptResultGetGlobalContext*(
    jsResult: ptr WebKitJavascriptResult): ptr JSCContext
  {.importc: "webkit_javascript_result_get_global_context",
      header: "webkit2/webkit2.h", cdecl.}

proc webkitJavascriptResultGetJsValue*(
    jsResult: ptr WebKitJavascriptResult): ptr JSCValue
  {.importc: "webkit_javascript_result_get_js_value",
      header: "webkit2/webkit2.h", cdecl.}

proc webkitJavascriptResultUnref*(jsResult: ptr WebKitJavascriptResult)
  {.importc: "webkit_javascript_result_unref", header: "webkit2/webkit2.h",
      cdecl.}

proc webkitSettingsNew*(): ptr WebKitSettings
  {.importc: "webkit_settings_new", header: "webkit2/webkit2.h", cdecl.}

proc webkitSettingsSetAllowFileAccessFromFileUrls*(settings: ptr WebKitSettings;
    allowed: GBoolean)
  {.importc: "webkit_settings_set_allow_file_access_from_file_urls",
      header: "webkit2/webkit2.h", cdecl.}

proc webkitSettingsSetDeveloperExtrasEnabled*(settings: ptr WebKitSettings;
    enabled: GBoolean)
  {.importc: "webkit_settings_set_developer_extras_enabled",
      header: "webkit2/webkit2.h", cdecl.}

proc webkitSettingsSetEnableJavascript*(settings: ptr WebKitSettings;
    enabled: GBoolean)
  {.importc: "webkit_settings_set_enable_javascript",
      header: "webkit2/webkit2.h", cdecl.}

proc webkitUriSchemeRequestFinish*(request: ptr WebKitURISchemeRequest;
    stream: pointer; streamLength: int64; mimeType: cstring)
  {.importc: "webkit_uri_scheme_request_finish", header: "webkit2/webkit2.h",
      cdecl.}

proc webkitUriSchemeRequestFinishError*(request: ptr WebKitURISchemeRequest;
    error: ptr GError)
  {.importc: "webkit_uri_scheme_request_finish_error",
      header: "webkit2/webkit2.h", cdecl.}

proc webkitUriSchemeRequestGetHttpBody*(
    request: ptr WebKitURISchemeRequest): pointer
  {.importc: "webkit_uri_scheme_request_get_http_body",
      header: "webkit2/webkit2.h", cdecl.}

proc webkitUriSchemeRequestGetHttpHeaders*(
    request: ptr WebKitURISchemeRequest): ptr SoupMessageHeaders
  {.importc: "webkit_uri_scheme_request_get_http_headers",
      header: "webkit2/webkit2.h", cdecl.}

proc webkitUriSchemeRequestGetHttpMethod*(
    request: ptr WebKitURISchemeRequest): cstring
  {.importc: "webkit_uri_scheme_request_get_http_method",
      header: "webkit2/webkit2.h", cdecl.}

proc webkitUriSchemeRequestGetPath*(request: ptr WebKitURISchemeRequest): cstring
  {.importc: "webkit_uri_scheme_request_get_path", header: "webkit2/webkit2.h",
      cdecl.}

proc webkitUriSchemeRequestGetScheme*(
    request: ptr WebKitURISchemeRequest): cstring
  {.importc: "webkit_uri_scheme_request_get_scheme",
      header: "webkit2/webkit2.h", cdecl.}

proc webkitUriSchemeRequestGetUri*(request: ptr WebKitURISchemeRequest): cstring
  {.importc: "webkit_uri_scheme_request_get_uri", header: "webkit2/webkit2.h",
      cdecl.}

proc webkitUserContentManagerAddScript*(manager: ptr WebKitUserContentManager;
    script: ptr WebKitUserScript)
  {.importc: "webkit_user_content_manager_add_script",
      header: "webkit2/webkit2.h", cdecl.}

proc webkitUserContentManagerNew*(): ptr WebKitUserContentManager
  {.importc: "webkit_user_content_manager_new", header: "webkit2/webkit2.h",
      cdecl.}

proc webkitUserContentManagerRegisterScriptMessageHandler*(
    manager: ptr WebKitUserContentManager; name: cstring): GBoolean
  {.importc: "webkit_user_content_manager_register_script_message_handler",
      header: "webkit2/webkit2.h", cdecl.}

proc webkitUserContentManagerUnregisterScriptMessageHandler*(
    manager: ptr WebKitUserContentManager; name: cstring)
  {.importc: "webkit_user_content_manager_unregister_script_message_handler",
      header: "webkit2/webkit2.h", cdecl.}

proc webkitUserScriptNew*(source: cstring;
    injectedFrames: WebKitUserContentInjectedFrames;
    injectionTime: WebKitUserScriptInjectionTime; allowList,
    blockList: cstringArray): ptr WebKitUserScript
  {.importc: "webkit_user_script_new", header: "webkit2/webkit2.h", cdecl.}

proc webkitUserScriptUnref*(script: ptr WebKitUserScript)
  {.importc: "webkit_user_script_unref", header: "webkit2/webkit2.h", cdecl.}

proc webkitWebContextGetDefault*(): ptr WebKitWebContext
  {.importc: "webkit_web_context_get_default", header: "webkit2/webkit2.h",
      cdecl.}

proc webkitWebContextRegisterUriScheme*(context: ptr WebKitWebContext;
    scheme: cstring; callback: WebKitURISchemeRequestCallback;
        userData: pointer;
    destroyNotify: GDestroyNotify)
  {.importc: "webkit_web_context_register_uri_scheme",
      header: "webkit2/webkit2.h", cdecl.}

proc webkitWebViewEvaluateJavascript*(webView: ptr WebKitWebView;
    script: cstring; length: int64; worldName, sourceUri: cstring;
    cancellable: pointer; callback: pointer; userData: pointer)
  {.importc: "webkit_web_view_evaluate_javascript",
      header: "webkit2/webkit2.h", cdecl.}

proc webkitWebViewGetSettings*(webView: ptr WebKitWebView): ptr WebKitSettings
  {.importc: "webkit_web_view_get_settings", header: "webkit2/webkit2.h",
      cdecl.}

proc webkitWebViewLoadHtml*(webView: ptr WebKitWebView; content,
    baseUri: cstring)
  {.importc: "webkit_web_view_load_html", header: "webkit2/webkit2.h", cdecl.}

proc webkitWebViewLoadUri*(webView: ptr WebKitWebView; uri: cstring)
  {.importc: "webkit_web_view_load_uri", header: "webkit2/webkit2.h", cdecl.}

proc webkitWebViewNewWithUserContentManager*(
    manager: ptr WebKitUserContentManager): ptr GtkWidget
  {.importc: "webkit_web_view_new_with_user_content_manager",
      header: "webkit2/webkit2.h", cdecl.}

proc webkitWebViewSetSettings*(webView: ptr WebKitWebView;
    settings: ptr WebKitSettings)
  {.importc: "webkit_web_view_set_settings", header: "webkit2/webkit2.h",
      cdecl.}
