## Asset strategy knobs for the high-level app API.
##
## Embedded release builds may opt in to generated assets with
## `-d:viewyGeneratedAssets`. The generated module contract is:
##
##   - module name: `viewy_assets`
##   - exported const: `viewyEmbeddedHtml*: string`
##   - value: `staticRead` of the single-file Vite output, normally
##     `dist/index.html` after vite-plugin-singlefile has inlined JS/CSS.
##
## The generated file must be in a directory on Nim's import path. A CLI build
## should either stamp `viewy_assets.nim` into a source directory already passed
## to Nim, or add its generated directory with `--path:<dir>`. For example:
##
##   `const viewyEmbeddedHtml* = staticRead("dist/index.html")`
##
## Limitations of this zero-port mode are inherited from a single static HTML
## document: `public/` assets are not inlined by vite-plugin-singlefile, so
## templates should import files from `src/assets/`; SPA history routing also
## needs hash routing or served mode because there is no HTTP server to answer
## deep links.

when defined(viewyGeneratedAssets):
  import viewy_assets

import std/[strutils, tables]

import viewy/backend/api
import zippy

export AssetHandler, AssetRequest, AssetResponse, Header

type
  ServedAssetHandler* = AssetHandler
    ## Asset handler used by loopback served mode.
    ##
    ## Served mode invokes this handler on the dedicated HTTP server thread, not
    ## the backend UI thread. Captured state must be immutable after
    ## `startServedServer`/`run` and must not reference backend handles,
    ## `App`, or other UI-thread-owned mutable state.

type
  AssetMode* = enum
    ## Load a self-contained HTML document directly with the backend.
    assetsEmbedded
    ## Serve generated assets from a loopback-only authenticated HTTP server.
    assetsServedMode
    ## Navigate to a development server URL.
    assetsDevServer

  AssetTableItem* = object
    ## One generated frontend asset consumable by an `AssetHandler`.
    path*: string
      ## Absolute route path for the asset, for example `/index.html`.
    contentType*: string
      ## Content type returned for this asset.
    gzipBytes*: string
      ## Gzip-compressed response body bytes.

const
  generatedAssetsModuleName* = "viewy_assets"
    ## Generated Nim module name used by embedded asset mode.
  generatedEmbeddedHtmlSymbol* = "viewyEmbeddedHtml"
    ## Generated const name expected to contain the single-file HTML document.
  fallbackEmbeddedHtml* = "<!doctype html><meta charset=\"utf-8\"><div id=\"app\"></div>"
    ## Minimal HTML document used when no generated embedded assets are present.
  defaultEmbeddedHtml* = fallbackEmbeddedHtml
    ## Default HTML document passed to `newApp` for embedded asset mode.
  viewyDevUrl* {.strdefine: "viewyDev".} = "http://localhost:5173"
    ## Development server URL selected by `-d:viewyDev=<url>`.

when defined(viewyGeneratedServedAssets):
  const defaultAssetMode* = assetsServedMode
    ## Default asset mode selected at compile time.
else:
  const defaultAssetMode* = assetsEmbedded
    ## Default asset mode selected at compile time.

proc embeddedHtml*(): string =
  ## Return the HTML document used by embedded asset mode.
  ##
  ## When `-d:viewyGeneratedAssets` is enabled this comes from the generated
  ## `viewy_assets.viewyEmbeddedHtml` const. Otherwise it is a minimal fallback
  ## document, which keeps tests and library consumers compiling before the CLI
  ## build step stamps real frontend assets.
  when defined(viewyGeneratedAssets):
    viewy_assets.viewyEmbeddedHtml
  else:
    fallbackEmbeddedHtml

proc normalizeAssetPath*(path: string): string =
  ## Normalize generated asset-table keys into absolute route paths.
  ##
  ## This is not a complete security canonicalizer for untrusted native scheme
  ## requests; scheme backends must add traversal and decoding checks before
  ## using request paths as a trust boundary.
  result = path.replace("\\", "/")
  if result.len == 0:
    result = "/"
  if not result.startsWith("/"):
    result = "/" & result

proc rewriteAbsoluteAssetUrls*(html, prefix: string): string =
  ## Rewrite root-absolute frontend asset URLs under the served-mode prefix.
  result = html
  for attr in ["src", "href"]:
    result = result.replace(attr & "=\"/", attr & "=\"/" & prefix & "/")
    result = result.replace(attr & "='/", attr & "='/" & prefix & "/")

proc assetResponse*(status: int; statusText, mimeType, body: string;
    headers: openArray[Header] = []): AssetResponse =
  ## Build a complete asset response.
  AssetResponse(
    status: status,
    statusText: statusText,
    mimeType: mimeType,
    headers: @headers,
    body: body,
  )

proc hasAssetHeader*(headers: openArray[Header]; name: string): bool =
  ## Return true when an asset response/request header is present.
  for header in headers:
    if cmpIgnoreCase(header.name, name) == 0:
      return true

proc rewriteServedDocumentResponse*(response: var AssetResponse;
    prefix: string) =
  ## Apply loopback served-mode root-absolute URL rewriting to a document.
  if response.status != 200 or response.body.len == 0 or
      not response.headers.hasAssetHeader("Content-Encoding"):
    return
  try:
    response.body = compress(rewriteAbsoluteAssetUrls(uncompress(response.body),
      prefix))
  except CatchableError:
    discard

proc assetTableHandler*(assets: openArray[AssetTableItem];
    documentPath = "/index.html"; rewritePrefix = ""): AssetHandler =
  ## Return an `AssetHandler` backed by a generated asset table.
  ##
  ## The handler owns lookup and response construction for both loopback served
  ## mode and future native scheme backends. Authentication, scheme routing,
  ## and platform request adaptation stay outside this table adapter.
  var table: Table[string, AssetTableItem]
  let normalizedDocumentPath = normalizeAssetPath(documentPath)
  for asset in assets:
    var item = asset
    item.path = normalizeAssetPath(item.path)
    table[item.path] = item

  result = proc(request: AssetRequest): AssetResponse {.gcsafe.} =
    let requestPath = normalizeAssetPath(request.path)
    let assetPath = if requestPath == "/": normalizedDocumentPath else: requestPath
    if not table.hasKey(assetPath):
      return assetResponse(404, "Not Found", "text/plain; charset=utf-8",
        "not found", [Header((name: "Cache-Control", value: "no-store"))])

    let asset = table[assetPath]
    var responseBytes = asset.gzipBytes
    let content = if request.httpMethod == "HEAD": "" else: responseBytes
    result = assetResponse(200, "OK", asset.contentType, content, [
      Header((name: "Content-Encoding", value: "gzip")),
      Header((name: "Cache-Control", value: "no-store")),
    ])
    if assetPath == normalizedDocumentPath and rewritePrefix.len > 0 and
        request.httpMethod != "HEAD":
      result.rewriteServedDocumentResponse(rewritePrefix)
