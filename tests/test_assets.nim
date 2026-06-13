import std/strutils

import viewy/assets
import zippy

doAssert generatedAssetsModuleName == "viewy_assets"
doAssert generatedEmbeddedHtmlSymbol == "viewyEmbeddedHtml"
doAssert fallbackEmbeddedHtml == "<!doctype html><meta charset=\"utf-8\"><div id=\"app\"></div>"
doAssert embeddedHtml() == fallbackEmbeddedHtml

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

echo "ok: embedded asset contract"
