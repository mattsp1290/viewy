## Loopback HTTP server for served asset mode.

import std/[asyncdispatch, asynchttpserver, atomics, nativesockets, net, os,
    strutils, tables, uri]
import std/httpcore
import std/sysrand
import zippy

when defined(viewyGeneratedServedAssets):
  import viewy_assets

type
  ServedAsset* = object
    ## One gzip-compressed generated frontend asset.
    path*: string
      ## Absolute route path for the asset, for example `/index.html`.
    contentType*: string
      ## HTTP content type returned for this asset.
    gzipBytes*: string
      ## Gzip-compressed response body bytes.

  ServedModeError* = object of CatchableError
    ## Raised when served asset mode cannot start or serve generated assets.

  ServedServer* = ref object
    ## Running loopback server used by served asset mode.
    server: AsyncHttpServer
    thread: Thread[ServedServer]
    started: Atomic[bool]
    startFailed: Atomic[bool]
    stopRequested: Atomic[bool]
    assets: Table[string, ServedAsset]
    documentPath: string
    prefix: string
    documentToken: string
    sessionToken: string
    port: Port
    stopped: bool

proc servedModeError(message: string): ref ServedModeError =
  newException(ServedModeError, message)

proc hexToken(bytes: static[int]): string =
  var raw: array[bytes, byte]
  if not urandom(raw):
    raise servedModeError("failed to generate served-mode token")
  result = newStringOfCap(bytes * 2)
  const hex = "0123456789abcdef"
  for b in raw:
    result.add hex[int(b shr 4)]
    result.add hex[int(b and 0x0f)]

proc normalizeAssetPath(path: string): string =
  result = path.replace("\\", "/")
  if result.len == 0:
    result = "/"
  if not result.startsWith("/"):
    result = "/" & result

proc generatedServedAssets*(): seq[ServedAsset] =
  ## Return served assets from the generated `viewy_assets` module.
  when defined(viewyGeneratedServedAssets):
    for item in viewy_assets.viewyServedAssets:
      result.add ServedAsset(
        path: normalizeAssetPath(item.path),
        contentType: item.contentType,
        gzipBytes: item.gzipBytes,
      )
  else:
    @[]

proc generatedServedDocumentPath*(): string =
  ## Return the generated served-mode document path.
  when defined(viewyGeneratedServedAssets):
    normalizeAssetPath(viewy_assets.viewyServedDocumentPath)
  else:
    "/index.html"

proc findQueryParam(query, name: string): string =
  for part in query.split('&'):
    if part.len == 0:
      continue
    let eq = part.find('=')
    let key = if eq < 0: part else: part[0 ..< eq]
    if decodeUrl(key) == name:
      return if eq < 0: "" else: decodeUrl(part[eq + 1 .. ^1])

proc hasSessionCredential(headers: HttpHeaders; sessionToken: string): bool =
  let expected = "__viewy_session=" & sessionToken
  for cookie in headers.getOrDefault("Cookie").split(';'):
    if cookie.strip == expected:
      return true

  let auth = headers.getOrDefault("Authorization").strip
  auth == "Bearer " & sessionToken

proc headers(contentType: string; extra: openArray[(string, string)] = []): HttpHeaders =
  result = newHttpHeaders([
    ("Content-Type", contentType),
    ("Content-Encoding", "gzip"),
    ("Cache-Control", "no-store"),
  ])
  for (key, value) in extra:
    result[key] = value

proc rewriteAbsoluteAssetUrls(html, prefix: string): string =
  result = html
  for attr in ["src", "href"]:
    result = result.replace(attr & "=\"/", attr & "=\"/" & prefix & "/")
    result = result.replace(attr & "='/", attr & "='/" & prefix & "/")

proc textHeaders(): HttpHeaders =
  newHttpHeaders([
    ("Content-Type", "text/plain; charset=utf-8"),
    ("Cache-Control", "no-store"),
  ])

proc respondText(req: Request; code: HttpCode; message: string): Future[void] =
  req.respond(code, message, textHeaders())

proc routeAssetPath(s: ServedServer; requestPath: string): string =
  let base = "/" & s.prefix
  if requestPath == base or requestPath == base & "/":
    return s.documentPath
  if requestPath.startsWith(base & "/"):
    return normalizeAssetPath(requestPath[(base.len + 1) .. ^1])
  ""

proc isDocumentRoute(s: ServedServer; requestPath, assetPath: string): bool =
  let base = "/" & s.prefix
  assetPath == s.documentPath and (requestPath == base or requestPath == base & "/")

proc isRpcRoute(s: ServedServer; requestPath: string): bool =
  requestPath == "/" & s.prefix & "/__viewy_rpc" or
    requestPath.startsWith("/" & s.prefix & "/__viewy_rpc/")

proc handleRequest(s: ServedServer; req: Request): Future[void] {.async, gcsafe.} =
  if req.reqMethod != HttpGet and req.reqMethod != HttpHead:
    await req.respondText(Http405, "method not allowed")
    return

  let hasSession = hasSessionCredential(req.headers, s.sessionToken)
  if s.isRpcRoute(req.url.path):
    if not hasSession:
      await req.respondText(Http401, "unauthorized")
      return
    await req.respond(Http200,
      """{"error":{"message":"served HTTP RPC is not implemented","type":"NotImplementedError"}}""",
      newHttpHeaders([
        ("Content-Type", "application/json; charset=utf-8"),
        ("Cache-Control", "no-store"),
      ]))
    return

  let assetPath = s.routeAssetPath(req.url.path)
  if assetPath.len == 0:
    await req.respondText(Http401, "unauthorized")
    return
  var setCookie = ""
  if s.isDocumentRoute(req.url.path, assetPath) and not hasSession:
    let token = findQueryParam(req.url.query, "viewy_token")
    if token.len == 0 or token != s.documentToken:
      await req.respondText(Http401, "unauthorized")
      return
    s.documentToken = ""
    setCookie = "__viewy_session=" & s.sessionToken & "; Path=/" & s.prefix &
      "/; SameSite=Strict; HttpOnly"
  elif not hasSession:
    await req.respondText(Http401, "unauthorized")
    return

  if not s.assets.hasKey(assetPath):
    await req.respondText(Http404, "not found")
    return

  let asset = s.assets[assetPath]
  var extra: seq[(string, string)]
  if setCookie.len > 0:
    extra.add ("Set-Cookie", setCookie)
  var responseBytes = asset.gzipBytes
  if assetPath == s.documentPath and req.reqMethod != HttpHead:
    try:
      responseBytes = compress(rewriteAbsoluteAssetUrls(uncompress(
          asset.gzipBytes), s.prefix))
    except CatchableError:
      discard
  let content = if req.reqMethod == HttpHead: "" else: responseBytes
  await req.respond(Http200, content, headers(asset.contentType, extra))

proc serverLoop(s: ServedServer) {.thread.} =
  proc callback(req: Request): Future[void] {.async, gcsafe.} =
    await s.handleRequest(req)

  try:
    s.server = newAsyncHttpServer()
    s.server.listen(Port(0), "127.0.0.1")
    s.port = s.server.getPort()
    s.started.store(true)
  except CatchableError:
    s.startFailed.store(true)
    return

  try:
    while not s.stopRequested.load:
      try:
        if s.server.shouldAcceptRequest():
          let accepted = s.server.acceptRequest(callback)
          while not accepted.finished:
            poll(50)
          if accepted.failed:
            discard
        else:
          poll(50)
      except CatchableError:
        if not s.stopRequested.load:
          discard
  finally:
    try:
      s.server.close()
    except CatchableError:
      discard

proc stop*(s: ServedServer)

proc startServedServer*(assets: openArray[ServedAsset];
    documentPath = "/index.html"): ServedServer =
  ## Start a headless served-mode loopback server.
  if assets.len == 0:
    raise servedModeError("served mode has no generated assets")

  result = ServedServer(
    documentPath: normalizeAssetPath(documentPath),
    prefix: "__viewy_" & hexToken(8),
    documentToken: hexToken(24),
    sessionToken: hexToken(24),
  )

  for asset in assets:
    var item = asset
    item.path = normalizeAssetPath(item.path)
    result.assets[item.path] = item

  if not result.assets.hasKey(result.documentPath):
    raise servedModeError("served document not found: " & result.documentPath)

  createThread(result.thread, serverLoop, result)
  for _ in 0 ..< 500:
    if result.started.load:
      return
    if result.startFailed.load:
      joinThread(result.thread)
      raise servedModeError("served mode server failed to start")
    sleep(10)

  result.stop()
  raise servedModeError("served mode server did not report a port")

proc startGeneratedServedServer*(): ServedServer =
  ## Start a server from generated served-mode assets.
  startServedServer(generatedServedAssets(), generatedServedDocumentPath())

proc stop*(s: ServedServer) =
  ## Stop a served-mode server and join its thread.
  if s.isNil:
    return
  if s.stopped:
    return
  s.stopped = true
  s.stopRequested.store(true)
  if s.port.uint16 != 0:
    try:
      var wakeup = newSocket()
      wakeup.connect("127.0.0.1", s.port)
      wakeup.close()
    except OSError:
      discard
  joinThread(s.thread)

proc port*(s: ServedServer): Port =
  ## Return the selected loopback port.
  s.port

proc prefix*(s: ServedServer): string =
  ## Return the per-launch route prefix.
  s.prefix

proc documentUrl*(s: ServedServer): string =
  ## Return the initial one-time-token document URL.
  "http://127.0.0.1:" & $s.port.uint16 & "/" & s.prefix &
    "/?viewy_token=" & s.documentToken
