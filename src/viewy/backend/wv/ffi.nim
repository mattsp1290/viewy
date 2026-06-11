## Hand-written bindings for the vendored webview/webview 0.12.0 C API.
##
## Keep this module narrow: it intentionally wraps only the v1 surface used by
## viewy and does not expose webview_get_native_handle or webview_version.

import ./build

type
  Webview* = pointer
    ## Opaque `webview_t`.

  WebviewError* {.size: sizeof(cint).} = enum
    ## `webview_error_t` values from webview 0.12.0.
    wvMissingDependency = -5
    wvCanceled = -4
    wvInvalidState = -3
    wvInvalidArgument = -2
    wvUnspecified = -1
    wvOk = 0
    wvDuplicate = 1
    wvNotFound = 2

  WebviewHint* {.size: sizeof(cint).} = enum
    ## `webview_hint_t` values from webview 0.12.0.
    wvHintNone = 0
    wvHintMin = 1
    wvHintMax = 2
    wvHintFixed = 3

  WebviewDispatchCallback* = proc(w: Webview; arg: pointer) {.cdecl, gcsafe.}
    ## C callback used by `webview_dispatch`.

  WebviewBindCallback* = proc(id, req: cstring; arg: pointer) {.cdecl, gcsafe.}
    ## C callback used by `webview_bind`.

proc webviewCreate*(debug: cint; window: pointer): Webview
  {.importc: "webview_create", header: "webview.h", cdecl.}

proc webviewDestroy*(w: Webview): WebviewError
  {.importc: "webview_destroy", header: "webview.h", cdecl.}

proc webviewRun*(w: Webview): WebviewError
  {.importc: "webview_run", header: "webview.h", cdecl.}

proc webviewTerminate*(w: Webview): WebviewError
  {.importc: "webview_terminate", header: "webview.h", cdecl.}

proc webviewDispatch*(w: Webview; fn: WebviewDispatchCallback; arg: pointer): WebviewError
  {.importc: "webview_dispatch", header: "webview.h", cdecl.}

proc webviewBind*(w: Webview; name: cstring; fn: WebviewBindCallback;
    arg: pointer): WebviewError
  {.importc: "webview_bind", header: "webview.h", cdecl.}

proc webviewUnbind*(w: Webview; name: cstring): WebviewError
  {.importc: "webview_unbind", header: "webview.h", cdecl.}

proc webviewReturn*(w: Webview; id: cstring; status: cint; result: cstring): WebviewError
  {.importc: "webview_return", header: "webview.h", cdecl.}
  ## Complete a binding request.
  ##
  ## webview 0.12.0 maps status 0 to JavaScript promise resolution and any
  ## non-zero status to rejection. `result` must be a valid JSON value or an
  ## empty string, which yields JavaScript `undefined`.

proc webviewInit*(w: Webview; js: cstring): WebviewError
  {.importc: "webview_init", header: "webview.h", cdecl.}

proc webviewEval*(w: Webview; js: cstring): WebviewError
  {.importc: "webview_eval", header: "webview.h", cdecl.}

proc webviewSetHtml*(w: Webview; html: cstring): WebviewError
  {.importc: "webview_set_html", header: "webview.h", cdecl.}

proc webviewNavigate*(w: Webview; url: cstring): WebviewError
  {.importc: "webview_navigate", header: "webview.h", cdecl.}

proc webviewSetSize*(w: Webview; width, height: cint; hints: WebviewHint): WebviewError
  {.importc: "webview_set_size", header: "webview.h", cdecl.}

proc webviewSetTitle*(w: Webview; title: cstring): WebviewError
  {.importc: "webview_set_title", header: "webview.h", cdecl.}
