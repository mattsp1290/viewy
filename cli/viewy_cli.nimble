# Package

version = "0.1.0"
author = "Matt Spurlin"
description = "Command-line tooling for viewy desktop apps"
license = "MIT"
srcDir = "src"
paths = @["src"]
bin = @["viewy"]
installDirs = @["viewy_cli/templates"]

requires "nim >= 2.0.0"
requires "jsony == 1.1.6"
requires "zippy == 0.10.19"

task test, "Run the CLI test suite":
  exec "nim c --path:src -r tests/test_build.nim"
  exec "nim c --path:src -r tests/test_config.nim"
  exec "nim c --path:src -r tests/test_dev.nim"
  exec "nim c --path:src -r tests/test_doctor.nim"
  exec "nim c --path:src -r tests/test_dispatch.nim"
  exec "nim c --path:src -r tests/test_e2e.nim"
  exec "nim c --path:src -r tests/test_init.nim"
