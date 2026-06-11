import std/[os, osproc, strutils]

import viewy_cli/assets_gen
import viewy_cli/config

type
  BuildError* = object of CatchableError
  ExecProc* = proc(command, workingDir: string): tuple[output: string; exitCode: int]

proc buildError(message: string): ref BuildError =
  newException(BuildError, message)

proc quote(path: string): string =
  quoteShell(path)

proc defaultExec(command, workingDir: string): tuple[output: string; exitCode: int] =
  execCmdEx(command, workingDir = workingDir)

proc viewyModulePath(packagePath: string): string =
  if fileExists(packagePath / "viewy.nim"):
    return packagePath
  if fileExists(packagePath / "src" / "viewy.nim"):
    return packagePath / "src"
  ""

proc nimbleViewyLibPath(): string =
  let (output, exitCode) = execCmdEx("nimble path viewy")
  if exitCode != 0:
    return ""
  for line in output.splitLines:
    let path = line.strip
    if path.len == 0:
      continue
    result = viewyModulePath(path)
    if result.len > 0:
      return

proc viewyLibPath(): string =
  if existsEnv("VIEWY_LIB_SRC"):
    let fromEnv = getEnv("VIEWY_LIB_SRC")
    if dirExists(fromEnv):
      result = viewyModulePath(absolutePath(fromEnv))
      if result.len > 0:
        return
      raise buildError("VIEWY_LIB_SRC does not contain viewy.nim: " & fromEnv)
    raise buildError("VIEWY_LIB_SRC does not exist: " & fromEnv)

  let fromCheckout = parentDir(parentDir(parentDir(parentDir(currentSourcePath())))) / "src"
  if fileExists(fromCheckout / "viewy.nim"):
    return fromCheckout

  nimbleViewyLibPath()

proc checked(exec: ExecProc; command, workingDir: string) =
  let (output, exitCode) = exec(command, workingDir)
  if exitCode != 0:
    var message = "command failed: " & command
    if workingDir.len > 0:
      message.add " (cwd: " & workingDir & ")"
    if output.strip.len > 0:
      message.add "\n" & output.strip
    raise buildError(message)

proc exeName(name: string): string =
  when defined(windows):
    name & ".exe"
  else:
    name

proc plistValue(value: string): string =
  value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").
    replace("\"", "&quot;").replace("'", "&apos;")

proc emitMacBundle(cfg: ViewyConfig; binaryPath, buildDir: string): string =
  when defined(macosx):
    let appDir = buildDir / (cfg.name & ".app")
    let contents = appDir / "Contents"
    let macos = contents / "MacOS"
    createDir(macos)
    copyFile(binaryPath, macos / splitFile(binaryPath).name)
    writeFile(contents / "Info.plist", """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$1</string>
  <key>CFBundleIdentifier</key>
  <string>app.viewy.$2</string>
  <key>CFBundleName</key>
  <string>$3</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
</dict>
</plist>
""" % [splitFile(binaryPath).name.plistValue, cfg.name.plistValue,
      cfg.title.plistValue])
    result = appDir
  else:
    discard cfg
    discard binaryPath
    discard buildDir
    result = ""

proc buildApp*(cfg: ViewyConfig; release = false; projectDir = ".";
    exec: ExecProc = defaultExec): string =
  ## Build the configured app and return a human-readable summary.
  if cfg.assets != amSingle:
    raise buildError("viewy build currently supports only single-file assets")

  let root = absolutePath(projectDir)
  let frontendDir = root / cfg.frontendDir
  let nimMain = root / cfg.nimMain
  let nimSrcDir = parentDir(nimMain)
  let buildDir = root / "build"
  let distIndex = frontendDir / "dist" / "index.html"
  let generatedAssets = nimSrcDir / "viewy_assets.nim"
  let binaryPath = buildDir / exeName(cfg.name)

  if not dirExists(frontendDir):
    raise buildError("frontendDir not found: " & frontendDir)
  if not fileExists(nimMain):
    raise buildError("nimMain not found: " & nimMain)

  exec.checked("npm run build", frontendDir)
  generateSingleFileAssets(distIndex, generatedAssets)

  createDir(buildDir)
  var nimCmd = "nim c --mm:orc --threads:on -d:viewyGeneratedAssets --path:" &
    quote(nimSrcDir)
  let libPath = viewyLibPath()
  if libPath.len > 0:
    nimCmd.add " --path:" & quote(libPath)
  else:
    raise buildError("viewy library source not found; install the viewy package or set VIEWY_LIB_SRC")
  if release:
    nimCmd.add " -d:release -d:strip --opt:size"
  nimCmd.add " -o:" & quote(binaryPath) & " " & quote(nimMain)
  exec.checked(nimCmd, root)

  if not fileExists(binaryPath):
    raise buildError("nim did not produce expected binary: " & binaryPath)

  result = "Built frontend: " & frontendDir & "\n" &
    "Generated assets: " & generatedAssets & "\n" &
    "Built binary: " & binaryPath & " (" & $getFileSize(binaryPath) & " bytes)"

  let bundlePath = emitMacBundle(cfg, binaryPath, buildDir)
  if bundlePath.len > 0:
    result.add "\nBuilt app bundle: " & bundlePath
