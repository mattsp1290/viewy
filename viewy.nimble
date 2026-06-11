# Package

version       = "0.1.0"
author        = "Matt Spurlin"
description   = "A Tauri/Wails-style desktop app framework for Nim"
license       = "MIT"
srcDir        = "src"

# Dependencies
# Keep this list ruthless (spec §9): jsony for the RPC/JSON codec,
# zippy only for the Served asset mode (§4.5 option B).

requires "nim >= 2.0.0"
requires "jsony == 1.1.6"
requires "zippy == 0.10.19"

import std/os

task pretty, "Run nimpretty over the source tree (not yet gating in CI)":
  for root in ["src", "tests"]:
    for f in walkDirRec(root):
      if f.endsWith(".nim"):
        exec "nimpretty " & f
