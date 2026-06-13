import std/[os, parseopt, strutils]

import viewy_cli/assets_gen
import viewy_cli/build
import viewy_cli/config
import viewy_cli/dev
import viewy_cli/doctor
import viewy_cli/init

const CliVersion* = "0.1.0"

type
  CommandKind* = enum
    ckHelp
    ckVersion
    ckInit
    ckDev
    ckBuild
    ckDoctor

  Command* = object
    configPath*: string
    configExplicit*: bool
    case kind*: CommandKind
    of ckInit:
      name*: string
      templateName*: string
    of ckBuild:
      release*: bool
    else:
      discard

  CliResult* = object
    exitCode*: int
    output*: string
    error*: string
    command*: Command

  DispatchError* = object of CatchableError

proc usage*(): string =
  """
viewy - desktop app tooling for Nim

Usage:
  viewy init <name> [--template vanilla]
  viewy dev [--config viewy.json]
  viewy build [--release] [--config viewy.json]
  viewy doctor
  viewy --help
  viewy --version
""".strip()

proc dispatchError(message: string): ref DispatchError =
  newException(DispatchError, message)

proc parseCommand*(args: openArray[string]): Command =
  if args.len == 0:
    return Command(kind: ckHelp)

  var parser = initOptParser(@args, longNoVal = @["help", "version", "release"])
  var positionals: seq[string]
  var templateName = "vanilla"
  var templateExplicit = false
  var configPath = "viewy.json"
  var configExplicit = false
  var release = false

  for kind, key, val in parser.getopt():
    case kind
    of cmdArgument:
      positionals.add key
    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h":
        return Command(kind: ckHelp)
      of "version", "v":
        return Command(kind: ckVersion)
      of "template", "t":
        if val.len == 0:
          raise dispatchError("--template requires a value")
        templateName = val
        templateExplicit = true
      of "release":
        if val.len > 0:
          raise dispatchError("--release does not take a value")
        release = true
      of "config", "c":
        if val.len == 0:
          raise dispatchError("--config requires a value")
        configPath = val
        configExplicit = true
      else:
        raise dispatchError("unknown option: --" & key)
    of cmdEnd:
      discard

  if positionals.len == 0:
    return Command(kind: ckHelp)

  case positionals[0]
  of "init":
    if configExplicit:
      raise dispatchError("viewy init does not accept --config")
    if release:
      raise dispatchError("viewy init does not accept --release")
    if positionals.len != 2:
      raise dispatchError("usage: viewy init <name> [--template vanilla]")
    if templateName != "vanilla":
      raise dispatchError("unknown template: " & templateName & " (supported: vanilla)")
    Command(kind: ckInit, configPath: configPath,
      configExplicit: configExplicit,
      name: positionals[1], templateName: templateName)
  of "dev":
    if templateExplicit:
      raise dispatchError("viewy dev does not accept --template")
    if release:
      raise dispatchError("viewy dev does not accept --release")
    if positionals.len != 1:
      raise dispatchError("usage: viewy dev [--config viewy.json]")
    Command(kind: ckDev, configPath: configPath, configExplicit: configExplicit)
  of "build":
    if templateExplicit:
      raise dispatchError("viewy build does not accept --template")
    if positionals.len != 1:
      raise dispatchError("usage: viewy build [--release] [--config viewy.json]")
    Command(kind: ckBuild, configPath: configPath,
      configExplicit: configExplicit,
      release: release)
  of "doctor":
    if configExplicit or templateExplicit or release:
      raise dispatchError("viewy doctor does not accept command options yet")
    if positionals.len != 1:
      raise dispatchError("usage: viewy doctor")
    Command(kind: ckDoctor, configPath: configPath,
        configExplicit: configExplicit)
  else:
    raise dispatchError("unknown command: " & positionals[0])

proc runCli*(args: openArray[string]): CliResult =
  try:
    result.command = parseCommand(args)
  except DispatchError as e:
    return CliResult(exitCode: 2, error: e.msg & "\n\n" & usage())

  case result.command.kind
  of ckHelp:
    result.output = usage()
  of ckVersion:
    result.output = "viewy " & CliVersion
  of ckInit:
    try:
      result.output = initProject(result.command.name,
          result.command.templateName)
    except InitError as e:
      result.exitCode = 2
      result.error = e.msg
  of ckDev:
    try:
      let cfg = loadConfig(result.command.configPath,
        missingIsDefault = not result.command.configExplicit)
      let projectDir = if result.command.configExplicit:
        parentDir(absolutePath(result.command.configPath))
      else:
        "."
      runDev(cfg, projectDir)
    except ConfigError as e:
      result.exitCode = 2
      result.error = e.msg
    except DevError as e:
      result.exitCode = 2
      result.error = e.msg
  of ckBuild:
    try:
      let cfg = loadConfig(result.command.configPath,
        missingIsDefault = not result.command.configExplicit)
      let projectDir = if result.command.configExplicit:
        parentDir(absolutePath(result.command.configPath))
      else:
        "."
      result.output = buildApp(cfg, result.command.release, projectDir)
    except ConfigError as e:
      result.exitCode = 2
      result.error = e.msg
    except BuildError as e:
      result.exitCode = 2
      result.error = e.msg
    except AssetsGenError as e:
      result.exitCode = 2
      result.error = e.msg
  of ckDoctor:
    let report = runDoctor()
    result.output = report.output
    if not report.ok:
      result.exitCode = 1
