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
    ## Navigate to a development server URL.
    assetsDevServer

const
  generatedAssetsModuleName* = "viewy_assets"
  generatedEmbeddedHtmlSymbol* = "viewyEmbeddedHtml"
  fallbackEmbeddedHtml* = "<!doctype html><meta charset=\"utf-8\"><div id=\"app\"></div>"
  defaultEmbeddedHtml* = fallbackEmbeddedHtml
  viewyDevUrl* {.strdefine: "viewyDev".} = "http://localhost:5173"
    ## Development server URL selected by `-d:viewyDev=<url>`.

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
