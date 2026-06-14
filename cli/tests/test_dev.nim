import std/[net, os, strutils, tempfiles, times, unittest]

import viewy_cli/config
import viewy_cli/dev
import viewy_cli/procutil

suite "viewy dev":
  test "parses dev server endpoint":
    let endpoint = devServerEndpoint("http://127.0.0.1:5173")
    check endpoint.host == "127.0.0.1"
    check int(endpoint.port) == 5173

  test "rejects invalid dev URL port":
    expect DevError:
      discard devServerEndpoint("http://127.0.0.1:not-a-port")

  test "detects tcp readiness":
    var server = newSocket()
    server.bindAddr(Port(0), "127.0.0.1")
    server.listen()
    let port = server.getLocalAddr()[1]
    try:
      check isTcpReady("127.0.0.1", port)
    finally:
      server.close()

  test "rejects occupied dev port before spawning vite":
    var server = newSocket()
    server.bindAddr(Port(0), "127.0.0.1")
    server.listen()
    let port = server.getLocalAddr()[1]
    try:
      expect DevError:
        requireTcpFree("127.0.0.1", port)
    finally:
      server.close()

  test "dev readiness requires the spawned process to stay alive":
    var server = newSocket()
    server.bindAddr(Port(0), "127.0.0.1")
    server.listen()
    let port = server.getLocalAddr()[1]
    let child = startManagedProcess("short-lived", "nim", "", ["--version"])
    try:
      sleep(500)
      expect DevError:
        waitForDevServer(child, "127.0.0.1", port, timeoutMs = 1000)
    finally:
      stopManagedProcess(child)
      server.close()

  test "tracks latest Nim source mtime":
    let dir = createTempDir("viewy-dev-watch", "")
    try:
      createDir(dir / "src")
      let first = dir / "src" / "a.nim"
      let second = dir / "src" / "b.nim"
      writeFile(first, "echo 1\n")
      let firstMTime = latestNimMTime(dir / "src")
      sleep(1100)
      writeFile(second, "echo 2\n")
      check latestNimMTime(dir / "src").toUnixFloat > firstMTime.toUnixFloat
    finally:
      removeDir(dir)

  test "builds dev compile command":
    let dir = createTempDir("viewy-dev-cmd", "")
    try:
      createDir(dir / "src")
      writeFile(dir / "src" / "main.nim", "echo \"demo\"\n")
      let cfg = ViewyConfig(
        name: "demo",
        title: "Demo",
        width: 800,
        height: 600,
        resizable: true,
        assets: amSingle,
        devUrl: "http://127.0.0.1:5173",
        frontendDir: "frontend",
        nimMain: "src/main.nim",
      )
      let compiled = devCompileCommand(cfg, dir)
      check compiled.command.contains("-d:viewyDev=http://127.0.0.1:5173")
      when defined(linux) or defined(macosx) or defined(windows):
        check not compiled.command.contains("-d:viewyBackend=lite")
        check not compiled.command.contains("-d:viewyBackend=native")
      else:
        check compiled.command.contains("-d:viewyBackend=lite")
      check not compiled.command.contains("-d:debug")
      check compiled.command.contains("--mm:orc --threads:on")
      check compiled.binaryPath.contains("build" / "demo-dev")
    finally:
      removeDir(dir)
