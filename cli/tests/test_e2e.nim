import std/[os, osproc, strutils, tempfiles, unittest]

const CommandTimeoutMs = 180_000

let
  cliRoot = getCurrentDir()
  repoRoot = parentDir(cliRoot)
  templateRoot = cliRoot / "src" / "viewy_cli" / "templates"

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

proc writeCompilerConfig(appDir: string) =
  when defined(vcc):
    writeFile(appDir / "nim.cfg", "--cc:vcc\n")
  else:
    discard appDir

proc runGeneratedApp(binaryPath, appDir: string) =
  let oldQuit = getEnv("VIEWY_E2E_QUIT")
  let hadQuit = existsEnv("VIEWY_E2E_QUIT")
  try:
    putEnv("VIEWY_E2E_QUIT", "1")
    run(quote(binaryPath), appDir)
  finally:
    if hadQuit:
      putEnv("VIEWY_E2E_QUIT", oldQuit)
    else:
      delEnv("VIEWY_E2E_QUIT")

suite "viewy cli e2e":
  test "init, npm install, build release, and run vanilla app":
    let dir = createTempDir("viewy-e2e", "")
    let oldTemplateRoot = getEnv("VIEWY_TEMPLATE_ROOT")
    let hadTemplateRoot = existsEnv("VIEWY_TEMPLATE_ROOT")
    let oldLibSrc = getEnv("VIEWY_LIB_SRC")
    let hadLibSrc = existsEnv("VIEWY_LIB_SRC")
    try:
      putEnv("VIEWY_TEMPLATE_ROOT", templateRoot)
      putEnv("VIEWY_LIB_SRC", repoRoot)

      run("nimble build -y", cliRoot)
      run(quote(viewyExe) & " init demo-app --template vanilla", dir)

      let appDir = dir / "demo-app"
      check fileExists(appDir / "viewy.json")
      check fileExists(appDir / "demo_app.nimble")
      writeCompilerConfig(appDir)

      run("npm ci", appDir)
      run(quote(viewyExe) & " build --release", appDir)

      let
        binaryPath = appDir / "build" / exeName("demo-app")
        generatedAssets = appDir / "src" / "viewy_assets.nim"

      check fileExists(appDir / "dist" / "index.html")
      check fileExists(generatedAssets)
      check fileExists(binaryPath)
      check getFileSize(binaryPath) > 0

      runGeneratedApp(binaryPath, appDir)

      when defined(macosx):
        let
          appBundle = appDir / "build" / "demo-app.app"
          contents = appBundle / "Contents"
          macos = contents / "MacOS"
          bundledBinary = macos / "demo-app"
        check dirExists(appBundle)
        check fileExists(contents / "Info.plist")
        check fileExists(bundledBinary)
        let plist = readFile(contents / "Info.plist")
        check plist.contains("<string>demo-app</string>")
        check plist.contains("<key>NSHighResolutionCapable</key>")
        check plist.contains("<true/>")
        runGeneratedApp(bundledBinary, appDir)
        run("codesign --verify --deep " & quote(appBundle), appDir)
      when defined(windows):
        let
          manifest = appDir / "build" / "demo-app.manifest"
          rc = appDir / "build" / "demo-app.rc"
          manifestText = readFile(manifest)
        check fileExists(manifest)
        check fileExists(rc)
        check manifestText.startsWith("<?xml")
        check manifestText.contains("<assembly xmlns=\"urn:schemas-microsoft-com:asm.v1\" manifestVersion=\"1.0\">")
        check manifestText.contains("<dpiAwareness xmlns=\"http://schemas.microsoft.com/SMI/2016/WindowsSettings\">PerMonitorV2</dpiAwareness>")
        check manifestText.contains("<dpiAware xmlns=\"http://schemas.microsoft.com/SMI/2005/WindowsSettings\">true/pm</dpiAware>")
    finally:
      if hadTemplateRoot:
        putEnv("VIEWY_TEMPLATE_ROOT", oldTemplateRoot)
      else:
        delEnv("VIEWY_TEMPLATE_ROOT")
      if hadLibSrc:
        putEnv("VIEWY_LIB_SRC", oldLibSrc)
      else:
        delEnv("VIEWY_LIB_SRC")
      removeDir(dir)
