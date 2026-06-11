import std/[os]

import viewy_cli/dispatch

when isMainModule:
  let result = runCli(commandLineParams())
  if result.output.len > 0:
    echo result.output
  if result.error.len > 0:
    stderr.writeLine(result.error)
  quit(result.exitCode)
