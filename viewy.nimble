# Package

version = "0.2.0"
author = "Matt Spurlin"
description = "A Tauri/Wails-style desktop app framework for Nim"
license = "MIT"
srcDir = "src"
paths = @["src"]

# Dependencies
# Keep this list ruthless (spec §9): jsony for the RPC/JSON codec,
# zippy only for the Served asset mode (§4.5 option B).

requires "nim >= 2.0.0"
requires "jsony == 1.1.6"
requires "zippy == 0.10.19"

import std/[os, strutils]

task test, "Run the test suite against the current lite backend":
  for kind, f in walkDir("tests"):
    if kind == pcFile and f.endsWith(".nim"):
      exec "nim c -r --hints:off --mm:orc --threads:on " &
        "--outdir:build/tests --define:viewyBackend=lite " & f

task pretty, "Run nimpretty over Nim source files checked by CI":
  proc shouldFormat(path: string): bool =
    path.endsWith(".nim") or path.endsWith(".nimble")

  proc shouldSkip(path: string): bool =
    let normalized = path.replace("\\", "/")
    normalized.startsWith("tests/fixtures/") or
      normalized.contains("/node_modules/") or
      normalized.contains("/dist/") or
      normalized.contains("/build/") or
      normalized.contains("/.vite/")

  for f in ["viewy.nimble", "cli/viewy_cli.nimble"]:
    exec "nimpretty " & f

  for root in ["src", "cli/src", "cli/tests", "tests", "examples"]:
    for f in walkDirRec(root):
      if shouldFormat(f) and not shouldSkip(f):
        exec "nimpretty " & f
