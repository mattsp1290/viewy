import std/[os, strutils, tempfiles, unittest]

import viewy_cli/init

let templateRoot = getCurrentDir() / "templates"

proc fileCount(root: string): int =
  for path in walkDirRec(root):
    if fileExists(path):
      inc result

suite "viewy init":
  test "copies and stamps vanilla template":
    let dir = createTempDir("viewy-init", "")
    try:
      let output = initProject("demo-app", destRoot = dir, templateRoot = templateRoot)
      let appDir = dir / "demo-app"
      check output.contains("Created demo-app")
      check fileExists(appDir / "viewy.json")
      check fileExists(appDir / ".gitignore")
      check fileExists(appDir / "demo_app.nimble")
      check fileExists(appDir / "package.json")
      check fileExists(appDir / "src" / "main.nim")
      check fileExists(appDir / "src" / "assets" / "viewy.svg")
      check not dirExists(appDir / "public")
      check not dirExists(appDir / "dist")
      check not dirExists(appDir / "node_modules")
      check readFile(appDir / "viewy.json").contains("\"name\": \"demo-app\"")
      check readFile(appDir / "viewy.json").contains("\"title\": \"Demo app\"")
      check readFile(appDir / "package.json").contains("\"name\": \"demo-app\"")
      check readFile(appDir / "demo_app.nimble").contains("A viewy desktop app: Demo app")
      let old = getCurrentDir()
      try:
        setCurrentDir(appDir)
        check execShellCmd("npm ci") == 0
        check execShellCmd("npm run build") == 0
        check fileExists(appDir / "dist" / "index.html")
        check fileCount(appDir / "dist") == 1
      finally:
        setCurrentDir(old)
    finally:
      removeDir(dir)

  test "refuses non-empty destination":
    let dir = createTempDir("viewy-init-existing", "")
    try:
      createDir(dir / "demo")
      writeFile(dir / "demo" / "file.txt", "existing")
      expect InitError:
        discard initProject("demo", destRoot = dir, templateRoot = templateRoot)
    finally:
      removeDir(dir)

  test "rejects unavailable templates":
    expect InitError:
      discard initProject("demo", templateName = "react", templateRoot = templateRoot)

  test "rejects invalid project names":
    expect InitError:
      discard initProject("bad/name", templateRoot = templateRoot)

  test "compiled cli can init outside cli with explicit template root":
    let dir = createTempDir("viewy-init-cli", "")
    let old = getCurrentDir()
    try:
      check execShellCmd("nimble build -y") == 0
      setCurrentDir(dir)
      putEnv("VIEWY_TEMPLATE_ROOT", templateRoot)
      check execShellCmd(old / "viewy init cli-app --template vanilla") == 0
      check fileExists(dir / "cli-app" / "viewy.json")
      check fileExists(dir / "cli-app" / "cli_app.nimble")
    finally:
      delEnv("VIEWY_TEMPLATE_ROOT")
      setCurrentDir(old)
      removeDir(dir)
