## Shared WebView2 SDK pin for all Windows backends.
##
## The lite webview/webview backend and the native Windows COM declarations
## must target the same vendored Microsoft.Web.WebView2 SDK revision.

import std/strutils

proc slashPath(path: string): string {.compileTime.} =
  path.replace('\\', '/')

proc parentSlashDir(path: string): string {.compileTime.} =
  let slash = slashPath(path)
  let lastSlash = slash.rfind('/')
  if lastSlash < 0:
    "."
  else:
    slash[0 ..< lastSlash]

const
  moduleDir = parentSlashDir(currentSourcePath())
  repoRoot = moduleDir & "/../../.."

  webView2SdkPinPath* = repoRoot & "/vendor/webview2/PIN"
  webView2SdkVendorDir* = repoRoot & "/vendor/webview2"
  webView2SdkIncludeDir* = webView2SdkVendorDir & "/include"

  webView2ExpectedPackage* = "Microsoft.Web.WebView2"
  webView2ExpectedVersion* = "1.0.4022.49"

proc pinField(pinContents, key: string): string {.compileTime.} =
  let prefix = "# " & key & ": "
  for line in pinContents.splitLines:
    if line.startsWith(prefix):
      return line[prefix.len .. ^1].strip()
  raise newException(ValueError, "missing WebView2 PIN field: " & key)

const
  webView2SdkPinContents = staticRead(webView2SdkPinPath)
  webView2SdkPackage* = pinField(webView2SdkPinContents, "package")
  webView2SdkVersion* = pinField(webView2SdkPinContents, "version")

static:
  doAssert webView2SdkPackage == webView2ExpectedPackage,
    "vendor/webview2/PIN package changed; update Windows WebView2 ABI consumers"
  doAssert webView2SdkVersion == webView2ExpectedVersion,
    "vendor/webview2/PIN version changed; update Windows WebView2 ABI consumers"
