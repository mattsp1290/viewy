import std/strutils

import viewy/assets
import zippy

proc header(response: AssetResponse; name: string): string =
  for header in response.headers:
    if cmpIgnoreCase(header.name, name) == 0:
      return header.value

var seenQueries: seq[string]
let schemeHandler = assetTableHandler([
  AssetTableItem(
    path: "/index.html",
    contentType: "text/html; charset=utf-8",
    etag: "\"viewy-build\"",
    bytes: """<!doctype html><script src="/assets/app.js"></script>""",
    gzipBytes: compress("""<!doctype html><script src="/assets/app.js"></script>"""),
  ),
  AssetTableItem(
    path: "/assets/app.js",
    contentType: "text/javascript; charset=utf-8",
    etag: "\"viewy-build\"",
    bytes: "export const ok = true;",
    gzipBytes: compress("export const ok = true;"),
  ),
  AssetTableItem(
    path: "/assets/site.css",
    contentType: "text/css; charset=utf-8",
    etag: "\"viewy-build\"",
    bytes: "body{color:#111}",
    gzipBytes: compress("body{color:#111}"),
  ),
])

proc request(path: string; query = ""; headers: seq[Header] = @[]): AssetResponse =
  seenQueries.add query
  schemeHandler(AssetRequest(
    scheme: "viewy",
    httpMethod: "GET",
    path: path,
    query: query,
    headers: headers,
    body: "",
  ))

let document = request("/", "from=root")
doAssert document.status == 200
doAssert document.mimeType == "text/html; charset=utf-8"
doAssert document.header("Content-Encoding") == "gzip"
doAssert document.header("ETag") == "\"viewy-build\""
doAssert uncompress(document.body).contains("""src="/assets/app.js"""")

let js = request("/assets/app.js", "v=123")
doAssert js.status == 200
doAssert js.mimeType == "text/javascript; charset=utf-8"
doAssert uncompress(js.body) == "export const ok = true;"

let css = request("assets/site.css")
doAssert css.status == 200
doAssert css.mimeType == "text/css; charset=utf-8"
doAssert uncompress(css.body) == "body{color:#111}"

let spa = request("/settings/profile", "tab=account", @[
  Header((name: "Accept", value: "text/html,application/xhtml+xml")),
])
doAssert spa.status == 200
doAssert spa.mimeType == "text/html; charset=utf-8"
doAssert uncompress(spa.body).contains("""src="/assets/app.js"""")

let missingAsset = request("/assets/missing.js")
doAssert missingAsset.status == 404
doAssert missingAsset.body == "not found"

let missingNonHtmlRoute = request("/settings/profile", headers = @[
  Header((name: "Accept", value: "application/json")),
])
doAssert missingNonHtmlRoute.status == 404

for badPath in ["../secret", "/../secret", "/assets/%2e%2e/secret",
                "/assets/%252e%252e/secret", "/assets\\app.js",
                "viewy://app/assets/app.js", "//assets/app.js",
                "/assets/%00.js", "/assets/%zz.js", "/C:/windows"]:
  let response = request(badPath)
  doAssert response.status == 400
  doAssert response.body == "bad request"

doAssert seenQueries == @["from=root", "v=123", "", "tab=account", "", "", "",
    "", "", "", "", "", "", "", "", ""]

echo "ok: scheme asset routing"
