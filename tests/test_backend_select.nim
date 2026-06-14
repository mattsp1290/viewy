import std/[os, osproc, strutils, tempfiles, unittest]

proc nimCheck(source: string; flags: string = ""): tuple[output: string;
    exitCode: int] =
  let dir = createTempDir("viewy_backend_select_", "")
  try:
    let sample = dir / "check_backend_select.nim"
    writeFile(sample, source)
    execCmdEx("nim check --path:src " & flags & " " & quoteShell(sample))
  finally:
    removeDir(dir)

suite "backend selector":
  test "lite selection exports lite newBackend":
    let (output, exitCode) = nimCheck("""
import viewy/backend/select

let backend = newBackend()
doAssert backend.caps == {}
""", "-d:viewyBackend=lite")
    checkpoint output
    check exitCode == 0

  test "native selection exports platform backend on Linux, macOS, and Windows":
    let (output, exitCode) = nimCheck("""
import viewy/backend/select
let backend = newBackend()
doAssert backend.create != nil
doAssert backend.destroy != nil
doAssert backend.run != nil
doAssert backend.terminate != nil
doAssert backend.dispatchTerminate != nil
""")
    when defined(linux) or defined(macosx) or defined(windows):
      checkpoint output
      check exitCode == 0
    else:
      check exitCode != 0
      check output.contains("viewyBackend=native currently requires Linux or macOS")

  test "native selected caps are platform-specific":
    block:
      let (output, exitCode) = nimCheck("""
import viewy/backend/api
static:
  doAssert selectedBackendCaps == {capScheme}
""", "--os:linux -d:viewyBackend=native")
      checkpoint output
      check exitCode == 0

    block:
      let (output, exitCode) = nimCheck("""
import viewy/backend/api
static:
  doAssert selectedBackendCaps == {capScheme, capMenu, capTray, capWindowEvents}
""", "--os:macosx -d:viewyBackend=native")
      checkpoint output
      check exitCode == 0

    block:
      let (output, exitCode) = nimCheck("""
import viewy/backend/api
static:
  doAssert selectedBackendCaps == {capScheme, capMenu, capTray}
""", "--os:windows -d:viewyBackend=native")
      checkpoint output
      check exitCode == 0

    block:
      let (output, exitCode) = nimCheck("""
import viewy/backend/api
import viewy/backend/select
let backend = newBackend()
doAssert backend.create != nil
doAssert backend.run != nil
doAssert backend.dispatchTerminate != nil
doAssert capScheme in backend.caps
doAssert capMenu in backend.caps
doAssert capTray in backend.caps
""", "--os:windows -d:nimcheck -d:viewyBackend=native")
      checkpoint output
      check exitCode == 0

  test "native selection rejects gtk4 flag":
    let (output, exitCode) = nimCheck("""
import viewy/backend/select
discard newBackend()
""", "--os:linux -d:nimcheck -d:viewyBackend=native -d:viewyGtk4")
    check exitCode != 0
    check output.contains("-d:viewyGtk4 is only supported")

  test "direct native Linux backend import rejects gtk4 flag":
    let (output, exitCode) = nimCheck("""
import viewy/backend/native/linux/backend
discard newBackend()
""", "--os:linux -d:nimcheck -d:viewyGtk4")
    check exitCode != 0
    check output.contains("-d:viewyGtk4 is only supported")

  test "unsupported backend value fails clearly":
    let (output, exitCode) = nimCheck("""
import viewy/backend/select
""", "-d:viewyBackend=bogus")
    check exitCode != 0
    check output.contains("unsupported -d:viewyBackend value")
