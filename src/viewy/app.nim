## High-level App/Window API.

import std/asyncdispatch

import viewy/assets
import viewy/backend/api
import viewy/backend/select
import viewy/rpc
import viewy/runtime_js
from viewy/assets_served import ServedServer, documentUrl,
    startGeneratedServedServer, stop

type
  App* = ref object
    ## A configured native webview application.
    backend: Backend
    handle: BackendHandle
    title: string
    width: int
    height: int
    resizable: bool
    initiallyVisible: bool
    debug: bool
    assets: AssetMode
    assetHandler: ServedAssetHandler
    html: string
    devUrl: string
    windowEventHandlers: seq[WindowEventHandler]

  WindowEventHandler* = proc(event: WindowEvent) {.closure, gcsafe.}
    ## Callback invoked on the backend UI thread for native window lifecycle
    ## events.

proc newApp*(title = "viewy"; width = 1024; height = 768;
    resizable = true; assets = defaultAssetMode; html = defaultEmbeddedHtml;
    assetHandler: ServedAssetHandler = nil; devUrl = "http://localhost:5173";
        debug = false; initiallyVisible = true;
    backend = newBackend()): App =
  ## Create an app configuration.
  ##
  ## The default backend comes from `viewy/backend/select` and is chosen by
  ## `-d:viewyBackend`. Tests and alternate backends may pass a custom
  ## `Backend` vtable. `run` creates the native handle, injects the `__viewy`
  ## runtime, binds all `expose`d RPC procs, loads either embedded HTML or a
  ## dev-server URL, enters the blocking backend loop, then destroys the handle
  ## on exit.
  ##
  ## When `assets = assetsServedMode` or the current lite fallback for
  ## `assetsScheme` is active, `assetHandler` runs on the served-mode HTTP
  ## thread. It must capture only immutable state and must not touch backend
  ## handles or UI-thread-owned objects.
  App(
    backend: backend,
    title: title,
    width: width,
    height: height,
    resizable: resizable,
    initiallyVisible: initiallyVisible,
    debug: debug,
    assets: assets,
    assetHandler: assetHandler,
    html: html,
    devUrl: devUrl,
  )

proc invokeBinding(app: App; binding: RpcBinding; id,
    jsonArgs: string) {.gcsafe.} =
  let backend = app.backend
  let h = app.handle
  var pendingDone = false
  let resolver =
    proc(resolveId: string; ok: bool; json: string) {.gcsafe.} =
      backend.dispatchResolve(h, resolveId, ok, json)
      {.cast(gcsafe).}:
        pendingDone = true

  let reply = binding.callWithResolver(id, jsonArgs, resolver)
  if reply.pending:
    while not pendingDone:
      {.cast(gcsafe).}:
        poll(10)
  else:
    backend.dispatchResolve(h, id, reply.ok, reply.json)

proc bindRpc(app: App) =
  for binding in bindings():
    let rpc = binding
    app.backend.bindFn(app.handle, rpc.name,
      proc(id, jsonArgs: string) {.gcsafe.} =
      invokeBinding(app, rpc, id, jsonArgs)
    )

proc schemeHandler(app: App): AssetHandler =
  if not app.assetHandler.isNil:
    return app.assetHandler
  assetTableHandler(generatedSchemeAssetTable(), generatedSchemeDocumentPath())

proc requireAppBackendCap(app: App; cap: Capability; operation: string) =
  requireBackendCap(app.backend, cap, operation)

proc dispatchWindowEvent(app: App; event: WindowEvent) {.gcsafe.} =
  for handler in app.windowEventHandlers:
    handler(event)

proc bindWindowEvents(app: App) =
  if app.windowEventHandlers.len == 0:
    return
  app.requireAppBackendCap(capWindowEvents, "onWindowEvent")
  app.backend.onWindowEventImpl(app.handle,
    proc(event: WindowEvent) {.gcsafe.} =
    app.dispatchWindowEvent(event)
  )

proc run*(app: App) =
  ## Run the app until the backend event loop exits.
  ##
  ## This call blocks on the backend loop. It injects the `__viewy` runtime
  ## before page scripts run, registers every proc exposed through
  ## `viewy/rpc.expose`, loads content, and always destroys the backend handle
  ## after `run` returns or raises.
  var servedServer: ServedServer
  let useNativeScheme =
    when selectedBackend == "native":
      app.assets == assetsScheme and capScheme in app.backend.caps
    else:
      false
  when not defined(viewyDev):
    if app.assets == assetsServedMode or
        (app.assets == assetsScheme and not useNativeScheme):
      servedServer = startGeneratedServedServer(app.assetHandler)

  try:
    app.handle = app.backend.create(app.debug)
    app.backend.setTitle(app.handle, app.title)
    let hints = if app.resizable: whNone else: whFixed
    app.backend.setSize(app.handle, app.width, app.height, hints)
    app.backend.init(app.handle, viewyRuntimeJs)
    app.bindRpc()
    app.bindWindowEvents()
    when defined(viewyDev):
      app.backend.navigate(app.handle, viewyDevUrl)
    else:
      case app.assets
      of assetsDevServer:
        app.backend.navigate(app.handle, app.devUrl)
      of assetsServedMode:
        app.backend.navigate(app.handle, servedServer.documentUrl())
      of assetsScheme:
        if useNativeScheme:
          when selectedBackend == "native" and capScheme in selectedBackendCaps:
            app.backend.registerScheme(app.handle, "viewy", app.schemeHandler())
            app.backend.navigate(app.handle, "viewy://app/")
          else:
            app.backend.navigate(app.handle, servedServer.documentUrl())
        else:
          app.backend.navigate(app.handle, servedServer.documentUrl())
      of assetsEmbedded:
        let html = if app.html == defaultEmbeddedHtml: embeddedHtml() else: app.html
        app.backend.setHtml(app.handle, html)
    if not app.initiallyVisible:
      app.requireAppBackendCap(capWindowVisibility, "hideWindow")
      app.backend.hideWindowImpl(app.handle)
    app.backend.run(app.handle)
  finally:
    if app.handle != nil:
      app.backend.destroy(app.handle)
      app.handle = nil
    when not defined(viewyDev):
      servedServer.stop()

proc backend*(app: App): Backend =
  ## Return the backend vtable used by this app.
  app.backend

proc handle*(app: App): BackendHandle =
  ## Return the current backend handle, or nil before/after `run`.
  app.handle

proc onWindowEvent*(app: App; cb: WindowEventHandler) =
  ## Register a callback for native window lifecycle events.
  ##
  ## Call this before `run`. Backends invoke callbacks on their UI thread.
  ## Backends without `capWindowEvents` fail when `run` attempts to subscribe.
  doAssert not cb.isNil, "onWindowEvent callback must not be nil"
  doAssert app.handle == nil, "onWindowEvent must be registered before run"
  app.windowEventHandlers.add cb

proc on*(app: App; kind: WindowEventKind; cb: WindowEventHandler) =
  ## Register a callback for one native window lifecycle event kind.
  doAssert not cb.isNil, "on callback must not be nil"
  app.onWindowEvent(proc(event: WindowEvent) {.gcsafe.} =
    if event.kind == kind:
      cb(event)
  )

proc showWindow*(app: App) =
  ## Show the app's backing native window. Call after `run` has created the
  ## backend handle, typically from a UI-thread native callback such as a tray
  ## menu item.
  doAssert app.handle != nil, "showWindow requires a running app"
  app.requireAppBackendCap(capWindowVisibility, "showWindow")
  app.backend.showWindowImpl(app.handle)

proc hideWindow*(app: App) =
  ## Hide the app's backing native window without terminating the app. Call
  ## after `run` has created the backend handle, typically from a UI-thread
  ## native callback such as a tray menu item.
  doAssert app.handle != nil, "hideWindow requires a running app"
  app.requireAppBackendCap(capWindowVisibility, "hideWindow")
  app.backend.hideWindowImpl(app.handle)

proc showContextMenu*(app: App; options: ContextMenuOptions;
    cb: MenuCallback) =
  ## Show a native context menu for the running app.
  ##
  ## `x`/`y` in `options` are window-relative coordinates. Backends invoke
  ## `cb` on their UI thread when a menu item dispatches.
  doAssert app.handle != nil, "showContextMenu requires a running app"
  doAssert not cb.isNil, "showContextMenu callback must not be nil"
  app.requireAppBackendCap(capContextMenu, "showContextMenu")
  app.backend.showContextMenuImpl(app.handle, options, cb)

proc showContextMenu*(app: App; menu: seq[MenuItem]; x, y: int;
    cb: MenuCallback) =
  ## Show a native context menu at a window-relative point.
  app.showContextMenu(ContextMenuOptions(menu: menu, x: x, y: y), cb)
