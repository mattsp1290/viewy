import std/[httpclient, net, os, osproc, strutils, tempfiles, times, unittest]

const
  CommandTimeoutMs = 240_000
  DevLoopPort = Port(55973)

let
  cliRoot = getCurrentDir()
  repoRoot = parentDir(cliRoot)
  templateRoot = cliRoot / "templates"

proc exeName(name: string): string =
  when defined(windows):
    name & ".exe"
  else:
    name

proc quote(path: string): string =
  quoteShell(path)

let viewyExe = cliRoot / exeName("viewy")

proc run(command, workingDir: string) =
  let p = startProcess(command, workingDir = workingDir,
    options = {poEvalCommand, poParentStreams})
  let exitCode = waitForExit(p, CommandTimeoutMs)
  close(p)
  if exitCode != 0:
    checkpoint "command failed or timed out: " & command
  check exitCode == 0

proc isTcpReady(host: string; port: Port): bool =
  var socket = newSocket()
  try:
    socket.connect(host, port, timeout = 250)
    true
  except OSError:
    false
  finally:
    socket.close()

proc requirePortFree(port: Port) =
  check not isTcpReady("127.0.0.1", port)

proc waitFor(condition: proc(): bool; label: string; timeoutMs = 120_000) =
  let deadline = epochTime() + float(timeoutMs) / 1000.0
  while epochTime() < deadline:
    if condition():
      return
    sleep(100)
  checkpoint "timed out waiting for " & label
  check false

proc probeMain(revision: string): string =
  """
import std/os
import viewy

when defined(viewyDev):
  import viewy/backend/wv/backend

const revision = "$1"

proc appendLine(path, line: string) =
  var file = open(path, fmAppend)
  try:
    file.writeLine(line)
  finally:
    file.close()

when isMainModule:
  when defined(viewyDev):
    let marker = getEnv("VIEWY_DEVLOOP_MARKER")
    if marker.len > 0:
      appendLine(marker, "start:" & revision)
      let b = newBackend()
      let h = b.create(false)
      b.setTitle(h, "viewy app")
      b.init(h, viewyRuntimeJs)
      b.navigate(h, viewyDevUrl)
      b.run(h)
      b.destroy(h)
    else:
      newApp(title = "viewy app").run()
    if marker.len > 0:
      appendLine(marker, "stop:" & revision)
  else:
    newApp(title = "viewy app").run()
""" % [revision]

proc markerText(path: string): string =
  if fileExists(path):
    readFile(path)
  else:
    ""

proc countLinesContaining(path, needle: string): int =
  for line in markerText(path).splitLines:
    if line.contains(needle):
      inc result

proc writeProbe(path, revision: string) =
  writeFile(path, probeMain(revision))

proc startDevProcess(appDir: string): Process =
  startProcess(viewyExe, workingDir = appDir, args = ["dev"],
    options = {poParentStreams})

proc requestInterrupt(child: Process) =
  if child == nil or not child.running():
    return
  when defined(posix):
    discard execCmd("kill -INT " & $child.processID())
  else:
    child.terminate()

proc forceStopProcess(child: Process) =
  if child == nil:
    return
  try:
    if child.running():
      child.terminate()
      for _ in 0 ..< 100:
        if not child.running():
          break
        sleep(100)
      if child.running():
        child.kill()
  finally:
    child.close()

proc waitForExitClean(child: Process; label: string; timeoutMs = 30_000) =
  let deadline = epochTime() + float(timeoutMs) / 1000.0
  while epochTime() < deadline:
    if child == nil or not child.running():
      return
    sleep(100)
  checkpoint "timed out waiting for clean exit: " & label
  check false

proc matchingProcesses(pattern: string): seq[string] =
  when defined(posix):
    let (output, exitCode) = execCmdEx("ps -eo pid=,args=")
    if exitCode != 0:
      return @[]
    for line in output.splitLines:
      let stripped = line.strip()
      let separator = stripped.find(' ')
      if separator < 0:
        continue
      let args = stripped[separator + 1 .. ^1].strip()
      if args.contains(pattern):
        result.add(stripped)
  else:
    discard pattern
    @[]

proc assertNoProcessMatching(pattern: string) =
  let matches = matchingProcesses(pattern)
  if matches.len > 0:
    checkpoint "unexpected matching processes for " & pattern & ": " &
      matches.join(" | ")
  check matches.len == 0

proc assertProcessMatching(pattern: string) =
  let matches = matchingProcesses(pattern)
  if matches.len == 0:
    checkpoint "no matching process for " & pattern
  check matches.len > 0

proc assertHttpContains(url, expected: string) =
  var client = newHttpClient(timeout = 2000)
  try:
    check client.getContent(url).contains(expected)
  finally:
    client.close()

suite "viewy dev loop":
  test "survives 10 consecutive backend edits and cleans up children":
    let dir = createTempDir("viewy-devloop", "")
    let marker = dir / "devloop.marker"
    let port = DevLoopPort
    let oldTemplateRoot = getEnv("VIEWY_TEMPLATE_ROOT")
    let hadTemplateRoot = existsEnv("VIEWY_TEMPLATE_ROOT")
    let oldLibSrc = getEnv("VIEWY_LIB_SRC")
    let hadLibSrc = existsEnv("VIEWY_LIB_SRC")
    let oldMarker = getEnv("VIEWY_DEVLOOP_MARKER")
    let hadMarker = existsEnv("VIEWY_DEVLOOP_MARKER")
    var dev: Process
    var appBinary = ""
    var vitePattern = ""
    try:
      requirePortFree(port)
      putEnv("VIEWY_TEMPLATE_ROOT", templateRoot)
      putEnv("VIEWY_LIB_SRC", repoRoot)
      putEnv("VIEWY_DEVLOOP_MARKER", marker)

      run("nimble build -y", cliRoot)
      run(quote(viewyExe) & " init devloop-app --template vanilla", dir)

      let appDir = dir / "devloop-app"
      let mainPath = appDir / "src" / "main.nim"
      appBinary = appDir / "build" / exeName("devloop-app-dev")
      vitePattern = "vite --host 127.0.0.1 --strictPort"

      var config = readFile(appDir / "viewy.json")
      config = config.replace("http://127.0.0.1:5173",
        "http://127.0.0.1:" & $int(port))
      writeFile(appDir / "viewy.json", config)

      var viteConfig = readFile(appDir / "vite.config.ts")
      viteConfig = viteConfig.replace("port: 5173", "port: " & $int(port))
      writeFile(appDir / "vite.config.ts", viteConfig)

      writeProbe(mainPath, "rev-00")
      run("npm ci", appDir)

      dev = startDevProcess(appDir)

      waitFor(proc(): bool = isTcpReady("127.0.0.1", port),
        "Vite dev server")
      waitFor(proc(): bool = countLinesContaining(marker, "start:rev-00") >= 1,
        "initial app launch")
      assertProcessMatching(appBinary)
      assertHttpContains("http://127.0.0.1:" & $int(port), "</html>")

      for i in 1 .. 10:
        sleep(1100)
        let revision = "rev-" & align($i, 2, '0')
        writeProbe(mainPath, revision)
        waitFor(proc(): bool =
          countLinesContaining(marker, "start:" & revision) >= 1,
          "app relaunch " & revision)
        assertProcessMatching(appBinary)
        assertHttpContains("http://127.0.0.1:" & $int(port), "</html>")

      requestInterrupt(dev)
      waitForExitClean(dev, "viewy dev")
      waitFor(proc(): bool = not isTcpReady("127.0.0.1", port),
        "Vite shutdown", timeoutMs = 30_000)

      let linesAfterStop = markerText(marker).splitLines.len
      sleep(1500)
      check markerText(marker).splitLines.len == linesAfterStop
      if appBinary.len > 0:
        assertNoProcessMatching(appBinary)
      if vitePattern.len > 0:
        assertNoProcessMatching(vitePattern)
    finally:
      forceStopProcess(dev)
      if hadTemplateRoot:
        putEnv("VIEWY_TEMPLATE_ROOT", oldTemplateRoot)
      else:
        delEnv("VIEWY_TEMPLATE_ROOT")
      if hadLibSrc:
        putEnv("VIEWY_LIB_SRC", oldLibSrc)
      else:
        delEnv("VIEWY_LIB_SRC")
      if hadMarker:
        putEnv("VIEWY_DEVLOOP_MARKER", oldMarker)
      else:
        delEnv("VIEWY_DEVLOOP_MARKER")
      removeDir(dir)
