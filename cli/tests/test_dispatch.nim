import std/[os, strutils, tempfiles, unittest]

import viewy_cli/dispatch

suite "viewy dispatch":
  test "defaults to help":
    let cmd = parseCommand([])
    check cmd.kind == ckHelp

  test "parses help and version flags":
    check parseCommand(["--help"]).kind == ckHelp
    check parseCommand(["-h"]).kind == ckHelp
    check parseCommand(["--version"]).kind == ckVersion
    check parseCommand(["-v"]).kind == ckVersion

  test "parses init with template":
    let cmd = parseCommand(["init", "demo", "--template", "vanilla"])
    check cmd.kind == ckInit
    check cmd.name == "demo"
    check cmd.templateName == "vanilla"

  test "rejects unknown template":
    expect DispatchError:
      discard parseCommand(["init", "demo", "--template", "solid"])
    expect DispatchError:
      discard parseCommand(["init", "demo", "--template", "react"])

  test "parses build release":
    let cmd = parseCommand(["build", "--release"])
    check cmd.kind == ckBuild
    check cmd.release
    check cmd.configPath == "viewy.json"

  test "parses explicit config path":
    let cmd = parseCommand(["dev", "--config", "app.viewy.json"])
    check cmd.kind == ckDev
    check cmd.configPath == "app.viewy.json"
    check cmd.configExplicit

  test "explicit missing config path fails":
    let result = runCli(["dev", "--config", "missing.viewy.json"])
    check result.exitCode == 2
    check result.error.contains("config file not found")

  test "build anchors explicit config paths to the config directory":
    let dir = createTempDir("viewy-dispatch-config", "")
    let old = getCurrentDir()
    try:
      let appDir = dir / "app"
      createDir(appDir)
      writeFile(appDir / "viewy.json", """
        {
          "name": "demo",
          "title": "Demo",
          "width": 800,
          "height": 600,
          "resizable": true,
          "assets": "single",
          "devUrl": "http://127.0.0.1:5173",
          "frontendDir": "frontend",
          "nimMain": "src/main.nim"
        }
      """)

      setCurrentDir(dir)
      let result = runCli(["build", "--config", appDir / "viewy.json"])

      check result.exitCode == 2
      check result.error.contains(appDir / "frontend")
      check not result.error.contains(dir / "frontend")
    finally:
      setCurrentDir(old)
      removeDir(dir)

  test "rejects options on unrelated commands":
    expect DispatchError:
      discard parseCommand(["init", "demo", "--release"])
    expect DispatchError:
      discard parseCommand(["init", "demo", "--config", "viewy.json"])
    expect DispatchError:
      discard parseCommand(["dev", "--template", "vanilla"])
    expect DispatchError:
      discard parseCommand(["doctor", "--config", "viewy.json"])

  test "reserves doctor command":
    let result = runCli(["doctor"])
    check result.exitCode == 0
    check result.command.kind == ckDoctor
    check result.output.contains("Phase 3")

  test "reports invalid command with usage":
    let result = runCli(["unknown"])
    check result.exitCode == 2
    check result.error.contains("unknown command")
    check result.error.contains("Usage:")
