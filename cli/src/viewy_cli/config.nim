import std/[os, strutils]

import jsony

type
  AssetMode* = enum
    amSingle = "single"
    amServed = "served"

  ViewyConfig* = object
    name*: string
    title*: string
    width*: int
    height*: int
    resizable*: bool
    assets*: AssetMode
    devUrl*: string
    frontendDir*: string
    nimMain*: string

  ConfigError* = object of CatchableError

const DefaultConfig* = ViewyConfig(
  name: "viewy-app",
  title: "viewy app",
  width: 1024,
  height: 768,
  resizable: true,
  assets: amSingle,
  devUrl: "http://127.0.0.1:5173",
  frontendDir: "frontend",
  nimMain: "src/main.nim"
)

proc newHook*(cfg: var ViewyConfig) =
  cfg = DefaultConfig

proc configError(message: string): ref ConfigError =
  newException(ConfigError, message)

proc validate*(cfg: ViewyConfig) =
  if cfg.name.strip.len == 0:
    raise configError("viewy.json: name must not be empty")
  if cfg.title.strip.len == 0:
    raise configError("viewy.json: title must not be empty")
  if cfg.width <= 0:
    raise configError("viewy.json: width must be greater than 0")
  if cfg.height <= 0:
    raise configError("viewy.json: height must be greater than 0")
  if cfg.devUrl.strip.len == 0:
    raise configError("viewy.json: devUrl must not be empty")
  if cfg.frontendDir.strip.len == 0:
    raise configError("viewy.json: frontendDir must not be empty")
  if cfg.nimMain.strip.len == 0:
    raise configError("viewy.json: nimMain must not be empty")

proc parseConfig*(json: string): ViewyConfig =
  try:
    result = json.fromJson(ViewyConfig)
  except CatchableError as e:
    raise configError("viewy.json: malformed config: " & e.msg)
  result.validate()

proc loadConfig*(path = "viewy.json"; missingIsDefault = true): ViewyConfig =
  if not fileExists(path):
    if not missingIsDefault:
      raise configError(path & ": config file not found")
    return DefaultConfig
  parseConfig(readFile(path))
