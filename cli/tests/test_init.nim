import std/[os, strutils, tempfiles, unittest]

import viewy_cli/init

let templateRoot = getCurrentDir() / "templates"

suite "viewy init":
  test "copies and stamps vanilla template":
    let dir = createTempDir("viewy-init", "")
    try:
      let output = initProject("demo-app", destRoot = dir, templateRoot = templateRoot)
      let appDir = dir / "demo-app"
      check output.contains("Created demo-app")
      check fileExists(appDir / "viewy.json")
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
        check execShellCmd("test $(find dist -type f | wc -l | tr -d ' ') = 1") == 0
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
