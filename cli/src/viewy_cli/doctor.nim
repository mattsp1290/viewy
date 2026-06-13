import std/[osproc, strutils]

type
  DoctorError* = object of CatchableError

  DoctorTarget* = enum
    dtLinux
    dtMacos
    dtWindows
    dtOther

  DoctorExec* = proc(command: string): tuple[output: string; exitCode: int]

  DoctorProbe* = object
    target*: DoctorTarget
    exec*: DoctorExec

  CheckResult = object
    name: string
    ok: bool
    detail: string
    hint: string

proc defaultExec(command: string): tuple[output: string; exitCode: int] =
  execCmdEx(command)

proc defaultTarget(): DoctorTarget =
  when defined(linux):
    dtLinux
  elif defined(macosx):
    dtMacos
  elif defined(windows):
    dtWindows
  else:
    dtOther

proc defaultProbe*(): DoctorProbe =
  DoctorProbe(target: defaultTarget(), exec: defaultExec)

proc run(exec: DoctorExec; command: string): tuple[output: string;
    exitCode: int] =
  if exec == nil:
    defaultExec(command)
  else:
    exec(command)

proc ok(name, detail: string): CheckResult =
  CheckResult(name: name, ok: true, detail: detail)

proc fail(name, detail, hint: string): CheckResult =
  CheckResult(name: name, ok: false, detail: detail, hint: hint)

proc firstNonEmptyLine(output: string): string =
  for line in output.splitLines:
    result = line.strip
    if result.len > 0:
      return
  result = ""

proc parseVersionTriple(text: string): tuple[ok: bool; major, minor, patch: int] =
  var i = 0
  while i < text.len:
    if text[i].isDigit:
      var parts: seq[int]
      var pos = i
      while true:
        var value = 0
        var sawDigit = false
        while pos < text.len and text[pos].isDigit:
          sawDigit = true
          value = value * 10 + ord(text[pos]) - ord('0')
          inc pos
        if not sawDigit:
          break
        parts.add value
        if pos >= text.len or text[pos] != '.':
          break
        inc pos
      if parts.len >= 2:
        return (true, parts[0], parts[1], if parts.len >= 3: parts[2] else: 0)
      i = pos
    inc i
  (false, 0, 0, 0)

proc nodeVersionOk(major, minor: int): bool =
  (major == 20 and minor >= 19) or
    (major == 22 and minor >= 12) or
    major > 22

proc checkNim(probe: DoctorProbe): CheckResult =
  let probeResult = probe.exec.run("nim --version")
  if probeResult.exitCode != 0:
    return fail("Nim", "nim not found",
      "Install Nim 2.0+ and ensure `nim` is on PATH.")
  let line = probeResult.output.firstNonEmptyLine()
  let version = parseVersionTriple(line)
  if version.ok:
    if version.major < 2:
      let found = $version.major & "." & $version.minor & "." & $version.patch
      return fail("Nim", "found " & found, "Upgrade to Nim 2.0+.")
    ok("Nim", "found " & $version.major & "." & $version.minor & "." &
        $version.patch)
  else:
    ok("Nim", "found " & line)

proc checkNode(probe: DoctorProbe): CheckResult =
  let probeResult = probe.exec.run("node --version")
  if probeResult.exitCode != 0:
    return fail("Node", "node not found",
      "Install Node 20.19+ or 22.12+ and ensure `node` is on PATH.")

  let line = probeResult.output.firstNonEmptyLine()
  let version = parseVersionTriple(line)
  if not version.ok:
    return fail("Node", "could not parse Node version: " & line,
      "Install Node 20.19+ or 22.12+.")
  if not nodeVersionOk(version.major, version.minor):
    return fail("Node", "found " & $version.major & "." & $version.minor & "." &
        $version.patch,
      "Upgrade to Node 20.19+ or 22.12+.")
  ok("Node", "found " & $version.major & "." & $version.minor & "." &
      $version.patch)

proc checkNpm(probe: DoctorProbe): CheckResult =
  let probeResult = probe.exec.run("npm --version")
  if probeResult.exitCode != 0:
    return fail("npm", "npm not found",
      "Install npm with Node and ensure `npm` is on PATH.")
  ok("npm", "found " & probeResult.output.firstNonEmptyLine())

proc checkLinuxWebKit(probe: DoctorProbe): seq[CheckResult] =
  let pkgConfig = probe.exec.run("pkg-config --version")
  if pkgConfig.exitCode != 0:
    return @[fail("pkg-config", "pkg-config not found",
      "Install pkg-config plus GTK/WebKitGTK development packages.")]

  result.add ok("pkg-config", "found " & pkgConfig.output.firstNonEmptyLine())
  let webkit41 = probe.exec.run("pkg-config --exists gtk+-3.0 webkit2gtk-4.1")
  if webkit41.exitCode == 0:
    let webkit41Version = probe.exec.run(
        "pkg-config --atleast-version=2.40 webkit2gtk-4.1")
    if webkit41Version.exitCode == 0:
      result.add ok("WebKitGTK native",
        "found gtk+-3.0 + webkit2gtk-4.1 >= 2.40")
      return
    result.add ok("WebKitGTK lite",
      "found gtk+-3.0 + webkit2gtk-4.1; native Linux requires webkit2gtk-4.1 >= 2.40")
    return

  let webkitGtk6 = probe.exec.run("pkg-config --exists gtk4 webkitgtk-6.0")
  if webkitGtk6.exitCode == 0:
    result.add ok("WebKitGTK lite GTK4",
      "found gtk4 + webkitgtk-6.0 for -d:viewyBackend=lite -d:viewyGtk4")
    return

  let webkit40 = probe.exec.run("pkg-config --exists gtk+-3.0 webkit2gtk-4.0")
  if webkit40.exitCode == 0:
    result.add ok("WebKitGTK lite GTK3 fallback",
      "found gtk+-3.0 + webkit2gtk-4.0 for -d:viewyBackend=lite")
  else:
    result.add fail("WebKitGTK",
      "native gtk+-3.0 + webkit2gtk-4.1, lite gtk+-3.0 + webkit2gtk-4.0, or lite gtk4 + webkitgtk-6.0 not found",
      "Install libgtk-3-dev with libwebkit2gtk-4.1-dev. GTK4/webkitgtk-6.0 is only for -d:viewyBackend=lite -d:viewyGtk4.")

proc checkMacosClt(probe: DoctorProbe): CheckResult =
  let probeResult = probe.exec.run("xcode-select -p")
  if probeResult.exitCode != 0:
    return fail("Xcode CLT", "Xcode command line tools not found",
      "Install with `xcode-select --install`.")
  ok("Xcode CLT", "found " & probeResult.output.firstNonEmptyLine())

proc checkWindowsWebView2(probe: DoctorProbe): CheckResult =
  const key = "{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
  for root in ["HKCU", "HKLM"]:
    for subkey in [
      root & "\\Software\\Microsoft\\EdgeUpdate\\Clients\\" & key,
      root & "\\Software\\WOW6432Node\\Microsoft\\EdgeUpdate\\Clients\\" & key,
    ]:
      let regResult = probe.exec.run("reg query " & subkey & " /v pv")
      if regResult.exitCode == 0:
        return ok("WebView2 runtime", "found Evergreen Runtime")
  fail("WebView2 runtime", "Evergreen Runtime not found",
    "Install the Microsoft Edge WebView2 Evergreen Runtime.")

proc platformChecks(probe: DoctorProbe): seq[CheckResult] =
  case probe.target
  of dtLinux:
    checkLinuxWebKit(probe)
  of dtMacos:
    @[checkMacosClt(probe)]
  of dtWindows:
    @[checkWindowsWebView2(probe)]
  of dtOther:
    @[fail("Platform", "unsupported platform",
      "viewy supports Linux, macOS, and Windows.")]

proc render(checks: openArray[CheckResult]): tuple[ok: bool; output: string] =
  result.ok = true
  result.output = "viewy doctor\n"
  for check in checks:
    if check.ok:
      result.output.add "OK   " & check.name & ": " & check.detail & "\n"
    else:
      result.ok = false
      result.output.add "FAIL " & check.name & ": " & check.detail & "\n"
      result.output.add "     hint: " & check.hint & "\n"

proc runDoctor*(probe = defaultProbe()): tuple[ok: bool; output: string] =
  var checks = @[
    checkNim(probe),
    checkNode(probe),
    checkNpm(probe),
  ]
  checks.add platformChecks(probe)
  render(checks)
