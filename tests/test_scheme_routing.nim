import std/[os, osproc, strutils, tempfiles]

import viewy/assets
import zippy

proc header(response: AssetResponse; name: string): string =
  for header in response.headers:
    if cmpIgnoreCase(header.name, name) == 0:
      return header.value

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

let dir = createTempDir("viewy_scheme_mime_", "")
try:
  createDir(dir / "src")
  createDir(dir / "dist" / "assets")
  writeFile(dir / "dist" / "index.html", "<!doctype html>")
  writeFile(dir / "dist" / "assets" / "app.mjs", "export default 1")
  writeFile(dir / "dist" / "assets" / "style.css", "body{}")
  writeFile(dir / "dist" / "assets" / "data.json", "{}")
  writeFile(dir / "dist" / "assets" / "logo.svg", "<svg></svg>")
  writeFile(dir / "dist" / "assets" / "module.wasm", "wasm")
  let generated = dir / "src" / "viewy_assets.nim"
  let generator = dir / "generate_scheme_assets.nim"
  writeFile(generator, """
import std/os

import viewy_cli/assets_gen

generateSchemeAssets(paramStr(1), paramStr(2))
""")
  let genCmd = "nim c -r --hints:off --mm:orc --threads:on --path:cli/src --path:src " &
    quoteShell(generator) & " " & quoteShell(dir / "dist") & " " &
    quoteShell(generated)
  let (genOutput, genExitCode) = execCmdEx(genCmd)
  doAssert genExitCode == 0, genOutput

  let sample = dir / "check_scheme_mime.nim"
  writeFile(sample, """
import viewy/assets

let table = generatedSchemeAssetTable()

proc contentType(path: string): string =
  for asset in table:
    if asset.path == path:
      return asset.contentType

doAssert contentType("/index.html") == "text/html; charset=utf-8"
doAssert contentType("/assets/app.mjs") == "text/javascript; charset=utf-8"
doAssert contentType("/assets/style.css") == "text/css; charset=utf-8"
doAssert contentType("/assets/data.json") == "application/json; charset=utf-8"
doAssert contentType("/assets/logo.svg") == "image/svg+xml"
doAssert contentType("/assets/module.wasm") == "application/wasm"
""")

  let cmd = "nim c -r --hints:off --mm:orc --threads:on --path:src --path:cli/src --path:" &
    quoteShell(dir / "src") & " -d:viewyBackend=lite -d:viewyGeneratedSchemeAssets " &
    quoteShell(sample)
  let (output, exitCode) = execCmdEx(cmd)
  doAssert exitCode == 0, output
finally:
  removeDir(dir)

echo "ok: scheme asset routing"
