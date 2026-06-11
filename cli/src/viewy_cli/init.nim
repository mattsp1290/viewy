import std/[os, strutils]

type
  InitError* = object of CatchableError

proc initError(message: string): ref InitError =
  newException(InitError, message)

proc isProjectName*(name: string): bool =
  if name.len == 0:
    return false
  for ch in name:
    if ch notin {'a'..'z', 'A'..'Z', '0'..'9', '_', '-'}:
      return false
  true

proc packageName(name: string): string =
  result = name
  result = result.replace("-", "_")

proc titleName(name: string): string =
  result = name.replace("-", " ").replace("_", " ")
  if result.len > 0:
    result[0] = result[0].toUpperAscii()

proc stampFile(path, appName: string) =
  var text = readFile(path)
  let pkg = packageName(appName)
  let title = titleName(appName)
  text = text.replace("viewy-app", appName)
  text = text.replace("viewy app", title)
  text = text.replace("viewy-vanilla-template", appName)
  text = text.replace("viewy_app.nimble", pkg & ".nimble")
  text = text.replace("A viewy desktop app", "A viewy desktop app: " & title)
  writeFile(path, text)

proc shouldSkipTemplatePath(rel: string): bool =
  let normalized = rel.replace("\\", "/")
  normalized == "dist" or normalized.startsWith("dist/") or
    normalized == "node_modules" or normalized.startsWith("node_modules/") or
    normalized == ".vite" or normalized.startsWith(".vite/")

proc copyTemplate(templateDir, destDir: string) =
  for path in walkDirRec(templateDir):
    let rel = relativePath(path, templateDir)
    if shouldSkipTemplatePath(rel):
      continue
    var target = destDir / rel
    if splitFile(target).name == "viewy_app" and splitFile(target).ext == ".nimble":
      target = destDir / "viewy_app.nimble"
    createDir(parentDir(target))
    copyFile(path, target)

proc initProject*(name: string; templateName = "vanilla"; destRoot = ".";
    templateRoot = ""): string =
  if templateName != "vanilla":
    raise initError("unknown template: " & templateName & " (supported: vanilla)")
  if not isProjectName(name):
    raise initError("project name must use only letters, numbers, '_' or '-'")

  let destDir = destRoot / name
  if dirExists(destDir):
    for _ in walkDir(destDir):
      raise initError(destDir & " already exists and is not empty")
  elif fileExists(destDir):
    raise initError(destDir & " already exists and is not a directory")
  else:
    createDir(destDir)

  let templates = if templateRoot.len > 0:
    templateRoot
  else:
    parentDir(parentDir(parentDir(currentSourcePath()))) / "templates"
  let source = templates / templateName
  if not dirExists(source):
    raise initError("template not found: " & templateName)

  copyTemplate(source, destDir)

  let oldNimble = destDir / "viewy_app.nimble"
  let newNimble = destDir / (packageName(name) & ".nimble")
  if fileExists(oldNimble):
    moveFile(oldNimble, newNimble)

  for path in walkDirRec(destDir):
    if fileExists(path):
      stampFile(path, name)

  result = "Created " & name & "\n\nNext steps:\n  cd " & name &
    "\n  npm ci\n  npm run build\n  nim c --mm:orc --threads:on src/main.nim"
