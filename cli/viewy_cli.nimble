# Package

version       = "0.1.0"
author        = "Matt Spurlin"
description   = "Command-line tooling for viewy desktop apps"
license       = "MIT"
srcDir        = "src"
bin           = @["viewy"]

requires "nim >= 2.0.0"
requires "jsony == 1.1.6"

task test, "Run the CLI test suite":
  exec "nim c --path:src -r tests/test_config.nim"
  exec "nim c --path:src -r tests/test_dispatch.nim"
