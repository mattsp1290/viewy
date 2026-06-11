import std/[parseopt, strutils]

import viewy_cli/config

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
  var configPath = "viewy.json"
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
      of "release":
        release = true
      of "config", "c":
        if val.len == 0:
          raise dispatchError("--config requires a value")
        configPath = val
      else:
        raise dispatchError("unknown option: --" & key)
    of cmdEnd:
      discard

  if positionals.len == 0:
    return Command(kind: ckHelp)

  case positionals[0]
  of "init":
    if positionals.len != 2:
      raise dispatchError("usage: viewy init <name> [--template vanilla]")
    if templateName notin ["vanilla", "react", "svelte"]:
      raise dispatchError("unknown template: " & templateName)
    Command(kind: ckInit, name: positionals[1], templateName: templateName)
  of "dev":
    if positionals.len != 1:
      raise dispatchError("usage: viewy dev [--config viewy.json]")
    Command(kind: ckDev, configPath: configPath)
  of "build":
    if positionals.len != 1:
      raise dispatchError("usage: viewy build [--release] [--config viewy.json]")
    Command(kind: ckBuild, configPath: configPath, release: release)
  of "doctor":
    if positionals.len != 1:
      raise dispatchError("usage: viewy doctor")
    Command(kind: ckDoctor)
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
    result.output = "viewy init is not implemented yet"
  of ckDev:
    try:
      discard loadConfig(result.command.configPath)
      result.output = "viewy dev is not implemented yet"
    except ConfigError as e:
      result.exitCode = 2
      result.error = e.msg
  of ckBuild:
    try:
      discard loadConfig(result.command.configPath)
      result.output = "viewy build is not implemented yet"
    except ConfigError as e:
      result.exitCode = 2
      result.error = e.msg
  of ckDoctor:
    result.output = "viewy doctor is reserved for Phase 3"
