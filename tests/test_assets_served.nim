import std/[httpclient, nativesockets, net, os, osproc, strutils, tempfiles,
    unittest]

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
