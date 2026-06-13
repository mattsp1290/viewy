import std/[os, strutils, tempfiles, unittest]

import viewy_cli/init

let templateRoot = getCurrentDir() / "templates"

suite "viewy init":
  test "copies and stamps vanilla template":
    let dir = createTempDir("viewy-init", "")
    try:
      let output = initProject("demo-app", destRoot = dir,
          templateRoot = templateRoot)
      let appDir = dir / "demo-app"
      check output.contains("Created demo-app")
      check output.contains("viewy build --release")
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
    finally:
      removeDir(dir)

  test "copies and stamps react template":
    let dir = createTempDir("viewy-init-react", "")
    try:
      let output = initProject("react-app", templateName = "react",
        destRoot = dir,
        templateRoot = templateRoot)
      let appDir = dir / "react-app"
      check output.contains("Created react-app")
      check output.contains("viewy build --release")
      check fileExists(appDir / "viewy.json")
      check fileExists(appDir / ".gitignore")
      check fileExists(appDir / "react_app.nimble")
      check fileExists(appDir / "package.json")
      check fileExists(appDir / "package-lock.json")
      check fileExists(appDir / "src" / "main.nim")
      check fileExists(appDir / "src" / "main.tsx")
      check fileExists(appDir / "src" / "assets" / "viewy.svg")
      check not fileExists(appDir / "src" / "main.ts")
      check not dirExists(appDir / "dist")
      check not dirExists(appDir / "node_modules")
      check readFile(appDir / "viewy.json").contains("\"name\": \"react-app\"")
      check readFile(appDir / "viewy.json").contains("\"title\": \"React app\"")
      check readFile(appDir / "package.json").contains("\"name\": \"react-app\"")
      check readFile(appDir / "package.json").contains("\"react\"")
      check readFile(appDir / "react_app.nimble").contains("A viewy desktop app: React app")
    finally:
      removeDir(dir)

  test "copies and stamps svelte template":
    let dir = createTempDir("viewy-init-svelte", "")
    try:
      let output = initProject("svelte-app", templateName = "svelte",
        destRoot = dir,
        templateRoot = templateRoot)
      let appDir = dir / "svelte-app"
      check output.contains("Created svelte-app")
      check output.contains("viewy build --release")
      check fileExists(appDir / "viewy.json")
      check fileExists(appDir / ".gitignore")
      check fileExists(appDir / "svelte_app.nimble")
      check fileExists(appDir / "package.json")
      check fileExists(appDir / "package-lock.json")
      check fileExists(appDir / "src" / "main.nim")
      check fileExists(appDir / "src" / "main.ts")
      check fileExists(appDir / "src" / "App.svelte")
      check fileExists(appDir / "src" / "assets" / "viewy.svg")
      check not dirExists(appDir / "dist")
      check not dirExists(appDir / "node_modules")
      check readFile(appDir / "viewy.json").contains("\"name\": \"svelte-app\"")
      check readFile(appDir / "viewy.json").contains("\"title\": \"Svelte app\"")
      check readFile(appDir / "package.json").contains("\"name\": \"svelte-app\"")
      check readFile(appDir / "package.json").contains("\"svelte\"")
      check readFile(appDir / "svelte_app.nimble").contains("A viewy desktop app: Svelte app")
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
      discard initProject("demo", templateName = "solid",
          templateRoot = templateRoot)

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
      check execShellCmd(old / "viewy init cli-app --template react") == 0
      check fileExists(dir / "cli-app" / "viewy.json")
      check fileExists(dir / "cli-app" / "cli_app.nimble")
      check fileExists(dir / "cli-app" / "src" / "main.tsx")
    finally:
      delEnv("VIEWY_TEMPLATE_ROOT")
      setCurrentDir(old)
      removeDir(dir)
