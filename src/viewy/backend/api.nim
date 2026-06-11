## Backend abstraction (spec section 4.1): the minimal vtable-style
## interface every webview backend must satisfy.

type
  BackendHandle* = pointer
    ## Opaque backend-owned native webview handle.

  WindowHints* = enum
    ## Window sizing hint passed through to the backend implementation.
    whNone
    whMin
    whMax
    whFixed

  DispatchProc* = proc() {.gcsafe.}
    ## Work item scheduled onto the backend UI thread.

  BindCallback* = proc(id, jsonArgs: string) {.gcsafe.}
    ## RPC callback invoked by the backend with a request id and raw JSON args.

  Backend* = object
    create*: proc(debug: bool): BackendHandle
      ## Main thread only. Create and return a backend handle; `debug`
      ## enables backend-specific developer tooling when available.

    destroy*: proc(h: BackendHandle)
      ## Main thread only. Destroy a handle after `run` has returned or the
      ## backend has otherwise been terminated.

    run*: proc(h: BackendHandle)
      ## Main thread only. Enter the backend event loop; this call blocks
      ## until the window terminates.

    terminate*: proc(h: BackendHandle)
      ## Main thread only. Request that the backend event loop stop.

    dispatch*: proc(h: BackendHandle, fn: DispatchProc)
      ## Thread-safe. Schedule `fn` to run on the backend UI thread. This is
      ## the only backend operation that may be called away from the main
      ## thread.

    setTitle*: proc(h: BackendHandle, title: string)
      ## Main thread only. Set the native window title.

    setSize*: proc(h: BackendHandle, width, height: int, hints: WindowHints)
      ## Main thread only. Set the native window size and sizing hint.

    navigate*: proc(h: BackendHandle, url: string)
      ## Main thread only. Navigate the webview to a URL, used for dev-server
      ## and served-asset modes.

    setHtml*: proc(h: BackendHandle, html: string)
      ## Main thread only. Load an HTML string directly into the webview.

    eval*: proc(h: BackendHandle, js: string)
      ## Main thread only. Evaluate JavaScript in the active page context.

    init*: proc(h: BackendHandle, js: string)
      ## Main thread only. Register JavaScript that the backend injects before
      ## page scripts run.

    bindFn*: proc(h: BackendHandle, name: string, cb: BindCallback)
      ## Main thread only. Bind a JavaScript-exposed function name to a Nim
      ## callback that receives the webview request id and raw JSON args.

    unbind*: proc(h: BackendHandle, name: string)
      ## Main thread only. Remove a previously bound JavaScript function.

    resolve*: proc(h: BackendHandle, id: string, ok: bool, jsonResult: string)
      ## Main thread only. Complete a pending bound-call promise. Backends map
      ## `ok = true` to a success status and `ok = false` to a rejection
      ## status; for `webview_return`, that is status 0 or 1 respectively.
