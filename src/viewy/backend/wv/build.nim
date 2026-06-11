## Build flags for the vendored webview/webview backend.
##
## This module is imported by `ffi.nim` so any real call site compiles and
## links the vendored `webview.cc` translation unit with the correct platform
## flags.

import std/os

const
  moduleDir = currentSourcePath().parentDir
  repoRoot = moduleDir / ".." / ".." / ".." / ".."
  webviewVendorDir = repoRoot / "vendor" / "webview"
  webview2VendorDir = repoRoot / "vendor" / "webview2" / "include"
  webviewStub = webviewVendorDir / "webview.cc"

{.passC: "-I" & webviewVendorDir & " -DWEBVIEW_STATIC=1".}

when defined(nimcheck):
  discard
elif defined(linux):
  import std/strutils

  proc pkgConfig(package: string): tuple[ok: bool; cflags, libs: string] {.compileTime.} =
    let cflags = gorge("pkg-config --cflags " & package).strip()
    if cflags.len == 0:
      return (false, "", "")
    let libs = gorge("pkg-config --libs " & package).strip()
    if libs.len == 0:
      return (false, "", "")
    (true, cflags, libs)

  const gtk = when defined(viewyGtk4):
    pkgConfig("gtk4 webkitgtk-6.0")
  else:
    block:
      let webkit41 = pkgConfig("gtk+-3.0 webkit2gtk-4.1")
      if webkit41.ok:
        webkit41
      else:
        pkgConfig("gtk+-3.0 webkit2gtk-4.0")

  when not gtk.ok:
    when defined(viewyGtk4):
      {.error: "install gtk4 and webkitgtk-6.0 development packages for viewyGtk4".}
    else:
      {.error: "install libwebkit2gtk-4.1-dev (or libwebkit2gtk-4.0-dev) and gtk+-3.0 development packages".}

  {.passC: gtk.cflags.}
  {.passL: gtk.libs.}
  {.compile(webviewStub, "-std=c++14 -DWEBVIEW_STATIC=1").}
elif defined(macosx):
  {.passL: "-framework WebKit -framework Cocoa".}
  {.compile(webviewStub, "-x objective-c++ -std=c++14 -DWEBVIEW_STATIC=1").}
elif defined(windows):
  {.passC: "-I" & webview2VendorDir &
    " -DWEBVIEW_EDGE=1 -DWEBVIEW_MSWEBVIEW2_BUILTIN_IMPL=1" &
    " -DWEBVIEW_MSWEBVIEW2_EXPLICIT_LINK=1".}
  when defined(vcc):
    {.passL: "advapi32.lib ole32.lib shell32.lib shlwapi.lib user32.lib version.lib".}
    {.compile(webviewStub, "/std:c++14 /DWEBVIEW_STATIC=1 /DWEBVIEW_EDGE=1").}
  else:
    {.passL: "-ladvapi32 -lole32 -lshell32 -lshlwapi -luser32 -lversion".}
    {.compile(webviewStub, "-std=c++14 -DWEBVIEW_STATIC=1 -DWEBVIEW_EDGE=1").}
else:
  {.error: "viewy webview backend supports linux, macOS, and windows only".}
