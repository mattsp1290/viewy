import std/[os, strutils, tempfiles, unittest]

import viewy_cli/assets_gen
import viewy_cli/build
import viewy_cli/config

suite "viewy build":
  test "generates staticRead assets relative to the app source dir":
    let dir = createTempDir("viewy-assets-gen", "")
    try:
      createDir(dir / "src")
      createDir(dir / "frontend" / "dist")
      writeFile(dir / "frontend" / "dist" / "index.html", "<!doctype html>")

      let outPath = dir / "src" / "viewy_assets.nim"
      generateSingleFileAssets(dir / "frontend" / "dist" / "index.html", outPath)

      let generated = readFile(outPath)
      check generated.contains("const viewyEmbeddedHtml* = staticRead(")
      check generated.contains("../frontend/dist/index.html")
    finally:
      removeDir(dir)

  test "runs frontend build, generates assets, compiles binary, and reports size":
    let dir = createTempDir("viewy-build", "")
    var calls: seq[tuple[command, workingDir: string]]
    try:
      createDir(dir / "src")
      createDir(dir / "frontend" / "dist")
      writeFile(dir / "src" / "main.nim", "echo \"hello\"\n")
      writeFile(dir / "frontend" / "dist" / "index.html", "<!doctype html>")

      let cfg = ViewyConfig(
        name: "demo",
        title: "Demo",
        width: 800,
        height: 600,
        resizable: true,
        assets: amSingle,
        devUrl: "http://127.0.0.1:5173",
        frontendDir: "frontend",
        nimMain: "src/main.nim"
      )

      proc fakeExec(command, workingDir: string): tuple[output: string; exitCode: int] =
        calls.add (command, workingDir)
        if command.startsWith("nim c "):
          createDir(dir / "build")
          when defined(windows):
            writeFile(dir / "build" / "demo.exe", "binary")
          else:
            writeFile(dir / "build" / "demo", "binary")
        ("", 0)

      let output = buildApp(cfg, release = true, projectDir = dir, exec = fakeExec)

      check calls.len == 2
      check calls[0] == ("npm run build", dir / "frontend")
      check calls[1].command.startsWith("nim c ")
      check calls[1].command.contains("-d:viewyGeneratedAssets")
      check calls[1].command.contains("-d:release")
      check calls[1].command.contains("-d:strip")
      check calls[1].command.contains("--opt:size")
      check calls[1].command.contains(dir / "src" / "main.nim")
      check fileExists(dir / "src" / "viewy_assets.nim")
      check output.contains("Built binary:")
      check output.contains("6 bytes")
    finally:
      removeDir(dir)

  test "rejects unsupported served asset mode":
    expect BuildError:
      discard buildApp(ViewyConfig(
        name: "demo",
        title: "Demo",
        width: 800,
        height: 600,
        resizable: true,
        assets: amServed,
        devUrl: "http://127.0.0.1:5173",
        frontendDir: "frontend",
        nimMain: "src/main.nim"
      ))

  test "reports invalid explicit viewy library source before compile":
    let dir = createTempDir("viewy-build-missing-lib", "")
    let old = getEnv("VIEWY_LIB_SRC")
    let hadOld = existsEnv("VIEWY_LIB_SRC")
    try:
      createDir(dir / "src")
      createDir(dir / "frontend" / "dist")
      createDir(dir / "not-viewy")
      writeFile(dir / "src" / "main.nim", "echo \"hello\"\n")
      writeFile(dir / "frontend" / "dist" / "index.html", "<!doctype html>")
      putEnv("VIEWY_LIB_SRC", dir / "not-viewy")

      let cfg = ViewyConfig(
        name: "demo",
        title: "Demo",
        width: 800,
        height: 600,
        resizable: true,
        assets: amSingle,
        devUrl: "http://127.0.0.1:5173",
        frontendDir: "frontend",
        nimMain: "src/main.nim"
      )

      proc fakeExec(command, workingDir: string): tuple[output: string; exitCode: int] =
        discard command
        discard workingDir
        ("", 0)

      expect BuildError:
        discard buildApp(cfg, projectDir = dir, exec = fakeExec)
    finally:
      if hadOld:
        putEnv("VIEWY_LIB_SRC", old)
      else:
        delEnv("VIEWY_LIB_SRC")
      removeDir(dir)
