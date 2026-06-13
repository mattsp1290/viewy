import std/[net, os, osproc, strutils, times, uri]

import viewy_cli/build
import viewy_cli/config
import viewy_cli/procutil

type
  DevError* = object of CatchableError

proc devError(message: string): ref DevError =
  newException(DevError, message)

proc quote(path: string): string =
  quoteShell(path)

proc exeName(name: string): string =
  when defined(windows):
    name & ".exe"
  else:
    name

proc devServerEndpoint*(devUrl: string): tuple[host: string; port: Port] =
  let parsed = parseUri(devUrl)
  if parsed.hostname.len == 0:
    raise devError("devUrl must include a host: " & devUrl)
  var portNumber = 0
  if parsed.port.len > 0:
    try:
      portNumber = parseInt(parsed.port)
    except ValueError:
      raise devError("devUrl has invalid port: " & devUrl)
  elif parsed.scheme == "https":
    portNumber = 443
  else:
    portNumber = 80
  if portNumber <= 0 or portNumber > 65535:
    raise devError("devUrl has invalid port: " & devUrl)
  (parsed.hostname, Port(portNumber))

proc isTcpReady*(host: string; port: Port): bool =
  var socket = newSocket()
  try:
    socket.connect(host, port, timeout = 250)
    true
  except OSError:
    false
  finally:
    socket.close()

proc waitForTcp*(host: string; port: Port; timeoutMs = 30000) =
  let deadline = epochTime() + float(timeoutMs) / 1000.0
  while epochTime() < deadline:
    if isTcpReady(host, port):
      return
    sleep(100)
  raise devError("timed out waiting for dev server at " & host & ":" & $int(port))

proc requireTcpFree*(host: string; port: Port) =
  if isTcpReady(host, port):
    raise devError("dev server port is already in use: " & host & ":" & $int(port))

proc waitForDevServer*(child: ManagedProcess; host: string; port: Port;
    timeoutMs = 30000) =
  let deadline = epochTime() + float(timeoutMs) / 1000.0
  while epochTime() < deadline:
    if child == nil or not child.isRunning():
      raise devError("Vite dev server exited before becoming ready")
    if isTcpReady(host, port):
      sleep(250)
      if child.isRunning():
        return
      raise devError("Vite dev server exited before becoming ready")
    sleep(100)
  raise devError("timed out waiting for dev server at " & host & ":" & $int(port))

proc latestNimMTime*(srcDir: string): Time =
  if not dirExists(srcDir):
    return fromUnix(0)
  for path in walkDirRec(srcDir):
    if path.endsWith(".nim"):
      let modified = getLastModificationTime(path)
      if modified.toUnixFloat > result.toUnixFloat:
        result = modified

proc devCompileCommand*(cfg: ViewyConfig; projectDir = "."): tuple[command,
    binaryPath: string] =
  let root = absolutePath(projectDir)
  let nimMain = root / cfg.nimMain
  let nimSrcDir = parentDir(nimMain)
  let buildDir = root / "build"
  let binaryPath = buildDir / exeName(cfg.name & "-dev")
  if not fileExists(nimMain):
    raise devError("nimMain not found: " & nimMain)
  let libPath = viewyLibPath()
  if libPath.len == 0:
    raise devError("viewy library source not found; install the viewy package or set VIEWY_LIB_SRC")
  var command = "nim c --mm:orc --threads:on " &
    quote("-d:viewyDev=" & cfg.devUrl) &
    " --path:" & quote(nimSrcDir) & " --path:" & quote(libPath) &
    " -o:" & quote(binaryPath) & " " & quote(nimMain)
  (command, binaryPath)

proc compileDevApp*(cfg: ViewyConfig; projectDir = "."): string =
  let root = absolutePath(projectDir)
  let buildDir = root / "build"
  createDir(buildDir)
  let compiled = devCompileCommand(cfg, root)
  let (output, exitCode) = execCmdEx(compiled.command, workingDir = root)
  if exitCode != 0:
    var message = "command failed: " & compiled.command
    if output.strip.len > 0:
      message.add "\n" & output.strip
    raise devError(message)
  if not fileExists(compiled.binaryPath):
    raise devError("nim did not produce expected binary: " &
        compiled.binaryPath)
  compiled.binaryPath

var stopRequested {.global.}: bool

proc requestStop() {.noconv.} =
  stopRequested = true

proc runDev*(cfg: ViewyConfig; projectDir = ".") =
  let root = absolutePath(projectDir)
  let frontendDir = root / cfg.frontendDir
  let nimMain = root / cfg.nimMain
  let nimSrcDir = parentDir(nimMain)
  if not dirExists(frontendDir):
    raise devError("frontendDir not found: " & frontendDir)

  let endpoint = devServerEndpoint(cfg.devUrl)
  stopRequested = false
  setControlCHook(requestStop)

  var vite: ManagedProcess
  var app: ManagedProcess
  try:
    requireTcpFree(endpoint.host, endpoint.port)
    vite = startManagedProcess("vite", "npm", frontendDir, ["run", "dev"])
    waitForDevServer(vite, endpoint.host, endpoint.port)

    var lastMTime = latestNimMTime(nimSrcDir)
    var binaryPath = compileDevApp(cfg, root)
    app = startManagedProcess("viewy app", binaryPath, root, [])

    while not stopRequested:
      sleep(250)
      let currentMTime = latestNimMTime(nimSrcDir)
      if currentMTime.toUnixFloat > lastMTime.toUnixFloat:
        lastMTime = currentMTime
        stopManagedProcess(app)
        binaryPath = compileDevApp(cfg, root)
        app = startManagedProcess("viewy app", binaryPath, root, [])

      if vite != nil and not vite.isRunning():
        raise devError("Vite dev server exited")
  finally:
    stopManagedProcess(app)
    stopManagedProcess(vite)
    unsetControlCHook()
