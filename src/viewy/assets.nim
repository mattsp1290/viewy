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

type
  AssetMode* = enum
    ## Load a self-contained HTML document directly with the backend.
    assetsEmbedded
    ## Serve generated assets from a loopback-only authenticated HTTP server.
    assetsServedMode
    ## Navigate to a development server URL.
    assetsDevServer

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
