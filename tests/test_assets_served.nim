import std/[httpclient, nativesockets, net, os, osproc, strutils, tempfiles,
    unittest]

import viewy/assets
import viewy/assets_served
import zippy

proc getStatus(resp: Response): int =
  parseInt(resp.status.split(' ')[0])

proc header(resp: Response; name: string): string =
  for key, value in resp.headers:
    if cmpIgnoreCase(key, name) == 0:
      return value

proc canConnect(port: Port): bool =
  var socket = newSocket()
  try:
    socket.connect("127.0.0.1", port)
    true
  except OSError:
    false
  finally:
    socket.close()

suite "served asset mode":
  test "generated served assets contract compiles":
    let dir = createTempDir("viewy_assets_served_generated_", "")
    try:
      createDir(dir / "served")
      writeFile(dir / "served" / "index.html.gz", "gz-html")
      writeFile(dir / "viewy_assets.nim", """
const viewyServedDocumentPath* = "/index.html"
const viewyServedAssets* = [
  (path: "/index.html", contentType: "text/html; charset=utf-8",
    gzipBytes: staticRead("served/index.html.gz")),
]
""")

      let sample = dir / "check_generated_served_assets.nim"
      writeFile(sample, """
import viewy/assets
import viewy/assets_served

doAssert defaultAssetMode == assetsServedMode
let servedAssets = generatedServedAssets()
doAssert generatedServedDocumentPath() == "/index.html"
doAssert servedAssets.len == 1
doAssert servedAssets[0].path == "/index.html"
doAssert servedAssets[0].contentType == "text/html; charset=utf-8"
doAssert servedAssets[0].gzipBytes == "gz-html"
""")

      let cmd = "nim c -r --hints:off --mm:orc --threads:on --path:src --path:" &
        quoteShell(dir) & " -d:viewyGeneratedServedAssets " & quoteShell(sample)
      let (output, exitCode) = execCmdEx(cmd)
      if exitCode != 0:
        checkpoint output
      check exitCode == 0
    finally:
      removeDir(dir)

  test "generated scheme assets select scheme default":
    let dir = createTempDir("viewy_assets_scheme_generated_", "")
    try:
      createDir(dir / "served")
      writeFile(dir / "served" / "index.html.gz", "gz-html")
      writeFile(dir / "viewy_assets.nim", """
const viewySchemeDocumentPath* = "/index.html"
const viewySchemeAssets* = [
  (path: "/index.html", mimeType: "text/html; charset=utf-8", etag: "\"viewy-abc\"",
    bytes: "<!doctype html>",
    gzipBytes: staticRead("served/index.html.gz")),
]
""")

      let sample = dir / "check_generated_scheme_assets.nim"
      writeFile(sample, """
import viewy/assets
import viewy/assets_served

doAssert defaultAssetMode == assetsScheme
let schemeAssets = generatedSchemeAssets()
doAssert generatedSchemeDocumentPath() == "/index.html"
doAssert schemeAssets.len == 1
doAssert schemeAssets[0].path == "/index.html"
doAssert schemeAssets[0].mimeType == "text/html; charset=utf-8"
doAssert schemeAssets[0].etag == "\"viewy-abc\""
doAssert schemeAssets[0].bytes == "<!doctype html>"
doAssert schemeAssets[0].gzipBytes == "gz-html"
let servedAssets = generatedServedAssets()
doAssert generatedServedDocumentPath() == "/index.html"
doAssert servedAssets.len == 1
doAssert servedAssets[0].path == "/index.html"
doAssert servedAssets[0].contentType == "text/html; charset=utf-8"
""")

      let cmd = "nim c -r --hints:off --mm:orc --threads:on --path:src --path:" &
        quoteShell(dir) & " -d:viewyGeneratedSchemeAssets " & quoteShell(sample)
      let (output, exitCode) = execCmdEx(cmd)
      if exitCode != 0:
        checkpoint output
      check exitCode == 0
    finally:
      removeDir(dir)

  test "generated scheme assets start served fallback server":
    let dir = createTempDir("viewy_assets_scheme_server_", "")
    try:
      createDir(dir / "served")
      writeFile(dir / "served" / "index.html.gz",
        compress("""<!doctype html><script src="/assets/app.js"></script>"""))
      writeFile(dir / "served" / "app.js.gz", compress("console.log(1)"))
      writeFile(dir / "viewy_assets.nim", """
const viewySchemeDocumentPath* = "/index.html"
const viewySchemeAssets* = [
  (path: "/index.html", mimeType: "text/html; charset=utf-8", etag: "\"viewy-abc\"",
    bytes: "<!doctype html><script src=\"/assets/app.js\"></script>",
    gzipBytes: staticRead("served/index.html.gz")),
  (path: "/assets/app.js", mimeType: "text/javascript; charset=utf-8", etag: "\"viewy-abc\"",
    bytes: "console.log(1)",
    gzipBytes: staticRead("served/app.js.gz")),
]
""")

      let sample = dir / "check_generated_scheme_server.nim"
      writeFile(sample, """
import std/[httpclient, strutils]

import viewy/assets_served
import zippy

proc getStatus(resp: Response): int =
  parseInt(resp.status.split(' ')[0])

proc header(resp: Response; name: string): string =
  for key, value in resp.headers:
    if cmpIgnoreCase(key, name) == 0:
      return value

proc main() =
  let server = startGeneratedServedServer()
  try:
    let base = "http://127.0.0.1:" & $server.port.uint16
    var client = newHttpClient()

    let doc = client.request(server.documentUrl())
    doAssert doc.getStatus == 200
    doAssert uncompress(doc.body).contains("src=\"/" & server.prefix & "/assets/app.js\"")
    let cookie = doc.header("set-cookie")
    doAssert cookie.contains("__viewy_session=")

    client.headers = newHttpHeaders({"Cookie": cookie.split(';')[0]})
    let asset = client.request(base & "/" & server.prefix & "/assets/app.js")
    doAssert asset.getStatus == 200
    doAssert asset.header("content-type").contains("text/javascript")
    doAssert asset.header("content-encoding") == "gzip"
    doAssert uncompress(asset.body) == "console.log(1)"
  finally:
    server.stop()

main()
""")

      let cmd = "nim c -r --hints:off --mm:orc --threads:on --path:src --path:" &
        quoteShell(dir) & " -d:viewyGeneratedSchemeAssets " & quoteShell(sample)
      let (output, exitCode) = execCmdEx(cmd)
      if exitCode != 0:
        checkpoint output
      check exitCode == 0
    finally:
      removeDir(dir)

  test "headless server enforces token and session auth":
    let server = startServedServer([
      ServedAsset(path: "/index.html", contentType: "text/html; charset=utf-8",
        gzipBytes: compress("""<!doctype html><script src="/assets/app.js"></script>""")),
      ServedAsset(path: "/assets/app.js",
        contentType: "text/javascript; charset=utf-8",
        gzipBytes: compress("console.log(1)")),
    ])
    defer: server.stop()

    let base = "http://127.0.0.1:" & $server.port.uint16
    let prefixPath = "/" & server.prefix
    var client = newHttpClient()

    let unauthAsset = client.request(base & prefixPath & "/assets/app.js")
    check unauthAsset.getStatus == 401

    let doc = client.request(server.documentUrl())
    check doc.getStatus == 200
    check uncompress(doc.body).contains("src=\"" & prefixPath & "/assets/app.js\"")
    let cookie = doc.header("set-cookie")
    check cookie.contains("__viewy_session=")
    check cookie.contains("Path=" & prefixPath & "/")
    check cookie.contains("HttpOnly")

    let replay = client.request(server.documentUrl())
    check replay.getStatus == 401

    client.headers = newHttpHeaders({"Cookie": cookie.split(';')[0]})
    let authedAsset = client.request(base & prefixPath & "/assets/app.js")
    check authedAsset.getStatus == 200
    check authedAsset.header("content-type").contains("text/javascript")
    check authedAsset.header("content-encoding") == "gzip"

    let rootClient = newHttpClient()
    let rootAbsoluteAsset = rootClient.request(base & "/assets/app.js")
    check rootAbsoluteAsset.getStatus == 401

    let unauthBadPath = rootClient.request(base & prefixPath &
        "/assets/%252e%252e/secret")
    check unauthBadPath.getStatus == 401

    let badPath = client.request(base & prefixPath & "/assets/%252e%252e/secret")
    check badPath.getStatus == 400

    let unauthRpcClient = newHttpClient()
    let unauthRpc = unauthRpcClient.request(base & prefixPath & "/__viewy_rpc")
    check unauthRpc.getStatus == 401

    let authedRpc = client.request(base & prefixPath & "/__viewy_rpc")
    check authedRpc.getStatus == 200
    check authedRpc.header("content-type").contains("application/json")
    check authedRpc.body.contains("\"error\"")
    check authedRpc.body.contains("\"type\"")

    server.stop()
    for _ in 0 ..< 50:
      if not canConnect(server.port):
        break
      sleep(20)
    check not canConnect(server.port)

  test "custom asset handler supplies served responses":
    var calls = 0

    proc customHandler(request: AssetRequest): AssetResponse {.gcsafe.} =
      {.cast(gcsafe).}:
        inc calls
      case request.path
      of "/index.html":
        assetResponse(200, "OK", "text/html; charset=utf-8",
          compress("""<!doctype html><script src="/assets/app.js"></script>"""), [
          Header((name: "Content-Encoding", value: "gzip")),
          Header((name: "Cache-Control", value: "no-store")),
        ])
      of "/assets/app.js":
        assetResponse(200, "OK", "text/javascript; charset=utf-8",
          compress("console.log('custom')"), [
          Header((name: "Content-Encoding", value: "gzip")),
          Header((name: "Cache-Control", value: "no-store")),
        ])
      of "/gone":
        assetResponse(304, "Not Modified", "", "")
      else:
        assetResponse(404, "Not Found", "text/plain; charset=utf-8", "not found")

    let server = startServedServer([
      ServedAsset(path: "/index.html", contentType: "text/html; charset=utf-8",
        gzipBytes: compress("<!doctype html><main>placeholder</main>")),
    ], assetHandler = customHandler)
    defer: server.stop()

    let
      base = "http://127.0.0.1:" & $server.port.uint16
      prefixPath = "/" & server.prefix

    let unauth = newHttpClient().request(base & prefixPath & "/assets/app.js")
    check unauth.getStatus == 401
    check calls == 0

    var client = newHttpClient()
    let doc = client.request(server.documentUrl())
    check doc.getStatus == 200
    check uncompress(doc.body).contains("src=\"" & prefixPath & "/assets/app.js\"")
    check calls == 1

    let cookie = doc.header("set-cookie")
    client.headers = newHttpHeaders({"Cookie": cookie.split(';')[0]})
    let asset = client.request(base & prefixPath & "/assets/app.js")
    check asset.getStatus == 200
    check uncompress(asset.body).contains("console.log('custom')")
    check calls == 2

    let notModified = client.request(base & prefixPath & "/gone")
    check notModified.getStatus == 304
