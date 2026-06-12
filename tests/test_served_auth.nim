import std/[httpclient, nativesockets, net, os, strutils, unittest]

import viewy/assets_served
import zippy

proc statusCode(resp: Response): int =
  parseInt(resp.status.split(' ')[0])

proc header(resp: Response; name: string): string =
  for key, value in resp.headers:
    if cmpIgnoreCase(key, name) == 0:
      return value

proc canConnect(host: string; port: Port): bool =
  var socket = newSocket()
  try:
    socket.connect(host, port)
    true
  except OSError:
    false
  finally:
    socket.close()

proc nonLoopbackHosts(): seq[string] =
  let primary = $getPrimaryIPAddr()
  if primary.len > 0 and primary != "0.0.0.0" and
      not primary.startsWith("127.") and primary != "::1":
    result.add primary

suite "served mode auth":
  test "headless server requires token or session credentials":
    let server = startServedServer([
      ServedAsset(path: "/index.html", contentType: "text/html; charset=utf-8",
        gzipBytes: compress("""<!doctype html><script src="/assets/app.js"></script>""")),
      ServedAsset(path: "/assets/app.js", contentType: "text/javascript; charset=utf-8",
        gzipBytes: compress("console.log(1)")),
    ])
    defer: server.stop()

    check server.documentUrl().startsWith("http://127.0.0.1:")
    check canConnect("127.0.0.1", server.port)
    let otherHosts = nonLoopbackHosts()
    if otherHosts.len == 0:
      checkpoint "no non-loopback interface available for negative bind check"
    else:
      for host in otherHosts:
        check not canConnect(host, server.port)

    let
      base = "http://127.0.0.1:" & $server.port.uint16
      prefixPath = "/" & server.prefix
      tokenQuery = server.documentUrl().split('?')[1]

    var unauth = newHttpClient()
    check unauth.request(base & prefixPath & "/assets/app.js").statusCode == 401
    check unauth.request(base & prefixPath & "/__viewy_rpc").statusCode == 401
    check unauth.request(base & prefixPath & "/__viewy_rpc?" & tokenQuery).statusCode == 401

    var client = newHttpClient()
    let document = client.request(server.documentUrl())
    check document.statusCode == 200
    check document.header("content-encoding") == "gzip"
    check uncompress(document.body).contains(prefixPath & "/assets/app.js")

    let cookie = document.header("set-cookie")
    check cookie.contains("__viewy_session=")
    check cookie.contains("Path=" & prefixPath & "/")
    check cookie.contains("HttpOnly")

    check client.request(server.documentUrl()).statusCode == 401

    client.headers = newHttpHeaders({"Cookie": cookie.split(';')[0]})
    check client.request(base & prefixPath & "/assets/app.js").statusCode == 200
    check client.request(base & "/assets/app.js").statusCode == 401

    let rpc = client.request(base & prefixPath & "/__viewy_rpc")
    check rpc.statusCode == 200
    check rpc.header("content-type").contains("application/json")
    check rpc.body.contains("\"error\"")
    check rpc.body.contains("\"type\"")

    server.stop()
    for _ in 0 ..< 50:
      if not canConnect("127.0.0.1", server.port):
        break
      sleep(20)
    check not canConnect("127.0.0.1", server.port)
