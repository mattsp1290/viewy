import std/[strutils, unittest]

import viewy_cli/dispatch

suite "viewy dispatch":
  test "defaults to help":
    let cmd = parseCommand([])
    check cmd.kind == ckHelp

  test "parses init with template":
    let cmd = parseCommand(["init", "demo", "--template", "vanilla"])
    check cmd.kind == ckInit
    check cmd.name == "demo"
    check cmd.templateName == "vanilla"

  test "rejects unknown template":
    expect DispatchError:
      discard parseCommand(["init", "demo", "--template", "solid"])

  test "parses build release":
    let cmd = parseCommand(["build", "--release"])
    check cmd.kind == ckBuild
    check cmd.release
    check cmd.configPath == "viewy.json"

  test "parses explicit config path":
    let cmd = parseCommand(["dev", "--config", "app.viewy.json"])
    check cmd.kind == ckDev
    check cmd.configPath == "app.viewy.json"

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
