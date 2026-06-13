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

  test "native selection fails until native backends exist":
    let (output, exitCode) = nimCheck("""
import viewy/backend/select
discard newBackend()
""")
    check exitCode != 0
    check output.contains("viewyBackend=native selected")

  test "unsupported backend value fails clearly":
    let (output, exitCode) = nimCheck("""
import viewy/backend/select
""", "-d:viewyBackend=bogus")
    check exitCode != 0
    check output.contains("unsupported -d:viewyBackend value")
