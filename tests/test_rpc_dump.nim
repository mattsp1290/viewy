import std/[json, os, osproc, sequtils, strutils, tempfiles]

proc main() =
  let dir = createTempDir("viewy_rpc_dump_", "")
  defer:
    removeDir(dir)

  let sample = dir / "sample_dump.nim"
  writeFile(sample, """
import viewy/rpc

expose greet(name: string): string =
  "hello " & name

expose add(a, b: int): int =
  a + b
""")

  let cmd = "nim c --hints:off --mm:orc --threads:on --path:src -d:viewyDumpBindings " &
    quoteShell(sample)
  let (output, exitCode) = execCmdEx(cmd)
  doAssert exitCode == 0, output

  let lines = output.splitLines.filterIt(it.strip.len > 0)
  doAssert lines.len == 2, output

  let first = parseJson(lines[0])
  doAssert first["name"].getStr == "greet"
  doAssert first["params"][0]["name"].getStr == "name"
  doAssert first["params"][0]["typ"].getStr == "string"
  doAssert first["returnType"].getStr == "string"
  doAssert first["async"].getBool == false

  let second = parseJson(lines[1])
  doAssert second["name"].getStr == "add"
  doAssert second["params"].len == 2
  doAssert second["returnType"].getStr == "int"

  echo "ok: rpc dump metadata"

main()
