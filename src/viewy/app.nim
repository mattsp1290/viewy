## High-level App/Window API.

import std/asyncdispatch

import viewy/assets
import viewy/backend/api
import viewy/backend/lite/backend
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
    debug: bool
    assets: AssetMode
    assetHandler: ServedAssetHandler
    html: string
    devUrl: string

proc newApp*(title = "viewy"; width = 1024; height = 768;
    resizable = true; assets = defaultAssetMode; html = defaultEmbeddedHtml;
    assetHandler: ServedAssetHandler = nil; devUrl = "http://localhost:5173";
        debug = false;
    backend = newBackend()): App =
  ## Create an app configuration.
  ##
  ## The default backend is the vendored webview implementation. Tests and
  ## alternate backends may pass a custom `Backend` vtable. `run` creates the
  ## native handle, injects the `__viewy` runtime, binds all `expose`d RPC
  ## procs, loads either embedded HTML or a dev-server URL, enters the blocking
  ## backend loop, then destroys the handle on exit.
  ##
  ## When `assets = assetsServedMode`, `assetHandler` runs on the served-mode
  ## HTTP thread. It must capture only immutable state and must not touch
  ## backend handles or UI-thread-owned objects.
  App(
    backend: backend,
    title: title,
    width: width,
    height: height,
    resizable: resizable,
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

proc run*(app: App) =
  ## Run the app until the backend event loop exits.
  ##
  ## This call blocks on the backend loop. It injects the `__viewy` runtime
  ## before page scripts run, registers every proc exposed through
  ## `viewy/rpc.expose`, loads content, and always destroys the backend handle
  ## after `run` returns or raises.
  var servedServer: ServedServer
  when not defined(viewyDev):
    if app.assets == assetsServedMode:
      servedServer = startGeneratedServedServer(app.assetHandler)

  try:
    app.handle = app.backend.create(app.debug)
    app.backend.setTitle(app.handle, app.title)
    let hints = if app.resizable: whNone else: whFixed
    app.backend.setSize(app.handle, app.width, app.height, hints)
    app.backend.init(app.handle, viewyRuntimeJs)
    app.bindRpc()
    when defined(viewyDev):
      app.backend.navigate(app.handle, viewyDevUrl)
    else:
      case app.assets
      of assetsDevServer:
        app.backend.navigate(app.handle, app.devUrl)
      of assetsServedMode:
        app.backend.navigate(app.handle, servedServer.documentUrl())
      of assetsEmbedded:
        let html = if app.html == defaultEmbeddedHtml: embeddedHtml() else: app.html
        app.backend.setHtml(app.handle, html)
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
