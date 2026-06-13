import std/strutils

import viewy/assets
import zippy

doAssert generatedAssetsModuleName == "viewy_assets"
doAssert generatedEmbeddedHtmlSymbol == "viewyEmbeddedHtml"
doAssert fallbackEmbeddedHtml == "<!doctype html><meta charset=\"utf-8\"><div id=\"app\"></div>"
doAssert embeddedHtml() == fallbackEmbeddedHtml

let root = canonicalizeAssetRequestPath("")
doAssert root.ok
doAssert root.path == "/"

let decoded = canonicalizeAssetRequestPath("assets/app%20one.js")
doAssert decoded.ok
doAssert decoded.path == "/assets/app one.js"

let normalized = canonicalizeAssetRequestPath("/assets/./app.js")
doAssert normalized.ok
doAssert normalized.path == "/assets/app.js"

let caseSensitive = canonicalizeAssetRequestPath("/Assets/App.js")
doAssert caseSensitive.ok
doAssert caseSensitive.path == "/Assets/App.js"

for badPath in ["../secret", "/../secret", "/assets/%2e%2e/secret",
                "/assets/%252e%252e/secret", "/assets\\app.js",
                "https://viewy.localhost/assets/app.js", "//assets/app.js",
                "/assets/%zz.js", "/C:/windows"]:
  let bad = canonicalizeAssetRequestPath(badPath)
  doAssert not bad.ok

let handler = assetTableHandler([
  AssetTableItem(path: "index.html", contentType: "text/html; charset=utf-8",
    gzipBytes: compress("""<!doctype html><script src="/assets/app.js"></script>""")),
  AssetTableItem(path: "/assets/app.js",
    contentType: "text/javascript; charset=utf-8",
    gzipBytes: compress("console.log(1)")),
], "/index.html", "__viewy_test")

let doc = handler(AssetRequest(scheme: "viewy", httpMethod: "GET", path: "/",
  query: "", headers: @[], body: ""))
doAssert doc.status == 200
doAssert doc.mimeType == "text/html; charset=utf-8"
doAssert doc.headers == @[
  Header((name: "Content-Encoding", value: "gzip")),
  Header((name: "Cache-Control", value: "no-store")),
]
doAssert uncompress(doc.body).contains("src=\"/__viewy_test/assets/app.js\"")

let head = handler(AssetRequest(scheme: "viewy", httpMethod: "HEAD",
  path: "/assets/app.js", query: "", headers: @[], body: ""))
doAssert head.status == 200
doAssert head.body == ""

let missing = handler(AssetRequest(scheme: "viewy", httpMethod: "GET",
  path: "/missing.js", query: "", headers: @[], body: ""))
doAssert missing.status == 404
doAssert missing.body == "not found"

let badRequest = handler(AssetRequest(scheme: "viewy", httpMethod: "GET",
  path: "/assets/%252e%252e/secret", query: "", headers: @[], body: ""))
doAssert badRequest.status == 400
doAssert badRequest.body == "bad request"

echo "ok: embedded asset contract"
