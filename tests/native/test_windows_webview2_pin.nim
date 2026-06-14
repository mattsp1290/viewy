import std/[os, osproc, strutils]

import viewy/backend/windows_webview2_pin

const pinContents = staticRead(webView2SdkPinPath)

proc isSha256(value: string): bool =
  if value.len != 64:
    return false
  for ch in value:
    if ch notin {'0'..'9', 'a'..'f', 'A'..'F'}:
      return false
  true

proc pinnedFiles(): seq[tuple[expected, path: string]] =
  for line in pinContents.splitLines:
    let stripped = line.strip()
    if stripped.len == 0 or stripped.startsWith("#"):
      continue
    let parts = stripped.splitWhitespace()
    doAssert parts.len == 2, "invalid WebView2 PIN hash line: " & line
    doAssert isSha256(parts[0]), "invalid WebView2 PIN sha256: " & parts[0]
    result.add((parts[0].toLowerAscii(), parts[1]))

proc fileSha256(path: string): string =
  when defined(windows):
    let (output, exitCode) = execCmdEx(
      "certutil -hashfile " & quoteShell(path) & " SHA256")
    doAssert exitCode == 0, output
    for line in output.splitLines:
      let candidate = line.strip().toLowerAscii()
      if isSha256(candidate):
        return candidate
    doAssert false, "certutil output did not include a SHA-256 hash: " & output
  elif defined(macosx):
    let (output, exitCode) = execCmdEx("shasum -a 256 " & quoteShell(path))
    doAssert exitCode == 0, output
    return output.splitWhitespace()[0].toLowerAscii()
  else:
    let (output, exitCode) = execCmdEx("sha256sum " & quoteShell(path))
    doAssert exitCode == 0, output
    return output.splitWhitespace()[0].toLowerAscii()

doAssert webView2SdkPackage == webView2ExpectedPackage
doAssert webView2SdkVersion == webView2ExpectedVersion
doAssert pinContents.contains("# package: " & webView2ExpectedPackage)
doAssert pinContents.contains("# version: " & webView2ExpectedVersion)

let hashes = pinnedFiles()
doAssert hashes.len > 0
for entry in hashes:
  let path = webView2SdkVendorDir / entry.path
  doAssert fileExists(path), "missing WebView2 pinned file: " & entry.path
  doAssert fileSha256(path) == entry.expected,
    "WebView2 pinned file hash mismatch: " & entry.path

echo "ok: WebView2 SDK ABI pin ", webView2SdkPackage, " ", webView2SdkVersion
