import std/[os, osproc, tempfiles]

proc main() =
  let dir = createTempDir("viewy_assets_generated_", "")
  defer:
    removeDir(dir)

  createDir(dir / "dist")
  writeFile(dir / "dist" / "index.html", "<!doctype html><main>generated</main>")
  writeFile(dir / "viewy_assets.nim",
    "const viewyEmbeddedHtml* = staticRead(\"dist/index.html\")\n")

  let sample = dir / "check_generated_assets.nim"
  writeFile(sample, """
import viewy/assets

doAssert generatedAssetsModuleName == "viewy_assets"
doAssert generatedEmbeddedHtmlSymbol == "viewyEmbeddedHtml"
doAssert embeddedHtml() == "<!doctype html><main>generated</main>"
""")

  let cmd = "nim c -r --hints:off --mm:orc --threads:on --path:src --path:" &
    quoteShell(dir) & " -d:viewyGeneratedAssets " & quoteShell(sample)
  let (output, exitCode) = execCmdEx(cmd)
  doAssert exitCode == 0, output

  echo "ok: generated embedded asset contract"

main()
