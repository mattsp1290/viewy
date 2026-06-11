import std/[os, osproc]

type
  ManagedProcess* = ref object
    process*: Process
    name*: string

proc startManagedProcess*(name, command, workingDir: string;
    args: openArray[string]): ManagedProcess =
  ## Start a long-lived child process attached to the parent's terminal.
  let process = startProcess(command, workingDir = workingDir, args = args,
    options = {poUsePath, poParentStreams, poDaemon})
  ManagedProcess(process: process, name: name)

proc isRunning*(child: ManagedProcess): bool =
  child != nil and child.process != nil and child.process.running()

proc stopManagedProcess*(child: ManagedProcess) =
  if child == nil or child.process == nil:
    return
  try:
    if child.process.running():
      when defined(posix):
        let pid = child.process.processID()
        if pid > 0:
          discard execCmd("kill -TERM -" & $pid)
        else:
          child.process.terminate()
      else:
        child.process.terminate()
      for i in 0 ..< 50:
        if not child.process.running():
          break
        sleep(100)
      if child.process.running():
        when defined(posix):
          let pid = child.process.processID()
          if pid > 0:
            discard execCmd("kill -KILL -" & $pid)
          else:
            child.process.kill()
        else:
          child.process.kill()
  finally:
    child.process.close()
    child.process = nil
