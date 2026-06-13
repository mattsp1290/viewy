import std/[os, osproc, sequtils, strutils, tempfiles]

proc main() =
  let dir = createTempDir("viewy_dump_bindings_", "")
  defer:
    removeDir(dir)

  let sample = dir / "sample_dump_bindings.nim"
  writeFile(sample, """
import std/asyncdispatch

import jsony
import viewy/rpc

type
  Todo = object
    title: string
    done: bool

proc delayedCount(todos: seq[Todo]): Future[int] {.async.} =
  todos.len

expose greet(name: string): string =
  "hello " & name

expose add(a, b: int): int =
  a + b

expose save(todo: Todo): Todo =
  todo

expose countLater(todos: seq[Todo]): Future[int] =
  delayedCount(todos)

expose flushLater(): asyncdispatch.Future[void] =
  sleepAsync(1)
""")

  let cmd = "nim c --hints:off --mm:orc --threads:on --path:src " &
    "-d:viewyDumpBindings " & quoteShell(sample)
  let (output, exitCode) = execCmdEx(cmd)
  doAssert exitCode == 0, output

  let actual = output.splitLines.filterIt(it.strip.len > 0).join("\n")
  let expected = [
    """{"name":"greet","params":[{"name":"name","typ":"string"}],"returnType":"string","async":false}""",
    """{"name":"add","params":[{"name":"a","typ":"int"},{"name":"b","typ":"int"}],"returnType":"int","async":false}""",
    """{"name":"save","params":[{"name":"todo","typ":"Todo"}],"returnType":"Todo","async":false}""",
    """{"name":"countLater","params":[{"name":"todos","typ":"seq[Todo]"}],"returnType":"int","async":true}""",
    """{"name":"flushLater","params":[],"returnType":"void","async":true}""",
  ].join("\n")

  doAssert actual == expected, "expected:\n" & expected & "\nactual:\n" & actual
  echo "ok: dump bindings golden metadata"

main()
