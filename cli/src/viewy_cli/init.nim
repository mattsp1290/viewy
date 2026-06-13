import std/[os, strutils]

const SupportedTemplates* = ["vanilla", "react", "svelte"]

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
  text = text.replace("viewy-react-template", appName)
  text = text.replace("viewy-svelte-template", appName)
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
    let targetParts = splitFile(target)
    if targetParts.name == "viewy_app" and targetParts.ext == ".nimble":
      target = destDir / "viewy_app.nimble"
    elif targetParts.name == "viewy_app" and targetParts.ext == ".pkgtemplate":
      target = destDir / "viewy_app.nimble"
    createDir(parentDir(target))
    copyFile(path, target)

proc defaultTemplateRoot(): string =
  if existsEnv("VIEWY_TEMPLATE_ROOT"):
    let fromEnv = getEnv("VIEWY_TEMPLATE_ROOT")
    if dirExists(fromEnv):
      return fromEnv
    raise initError("VIEWY_TEMPLATE_ROOT does not exist: " & fromEnv)

  let appDir = getAppDir()
  let nimbleDir = parentDir(appDir)
  for candidate in [
    appDir / "templates",
    appDir / "viewy_cli" / "templates",
    parentDir(appDir) / "share" / "viewy" / "templates",
    parentDir(currentSourcePath()) / "templates",
    parentDir(parentDir(parentDir(currentSourcePath()))) / "templates"
  ]:
    if dirExists(candidate):
      return candidate

  for packageRoot in [nimbleDir / "pkgs2", nimbleDir / "pkgs"]:
    if not dirExists(packageRoot):
      continue
    for kind, candidate in walkDir(packageRoot):
      if kind != pcDir:
        continue
      if not splitPath(candidate).tail.startsWith("viewy_cli-"):
        continue
      if dirExists(candidate / "viewy_cli" / "templates"):
        return candidate / "viewy_cli" / "templates"
      if dirExists(candidate / "templates"):
        return candidate / "templates"

  raise initError("template assets not found; reinstall viewy or set VIEWY_TEMPLATE_ROOT")

proc initProject*(name: string; templateName = "vanilla"; destRoot = ".";
    templateRoot = ""): string =
  if templateName notin SupportedTemplates:
    raise initError("unknown template: " & templateName &
      " (supported: " & SupportedTemplates.join(", ") & ")")
  if not isProjectName(name):
    raise initError("project name must use only letters, numbers, '_' or '-'")

  let templates = if templateRoot.len > 0:
    templateRoot
  else:
    defaultTemplateRoot()
  let source = templates / templateName
  if not dirExists(source):
    raise initError("template not found: " & templateName)

  let destDir = destRoot / name
  if dirExists(destDir):
    for _ in walkDir(destDir):
      raise initError(destDir & " already exists and is not empty")
  elif fileExists(destDir):
    raise initError(destDir & " already exists and is not a directory")

  createDir(destRoot)
  let staging = destRoot / ("." & name & ".viewy-init-tmp")
  if dirExists(staging):
    removeDir(staging)
  elif fileExists(staging):
    removeFile(staging)

  try:
    createDir(staging)
    copyTemplate(source, staging)

    let oldNimble = staging / "viewy_app.nimble"
    let newNimble = staging / (packageName(name) & ".nimble")
    if fileExists(oldNimble):
      moveFile(oldNimble, newNimble)

    for path in walkDirRec(staging):
      if fileExists(path):
        stampFile(path, name)

    moveDir(staging, destDir)
  except CatchableError:
    if dirExists(staging):
      removeDir(staging)
    raise

  result = "Created " & name & "\n\nNext steps:\n  cd " & name &
    "\n  npm ci\n  viewy build --release"
