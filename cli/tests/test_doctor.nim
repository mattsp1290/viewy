import std/[strutils, tables, unittest]

import viewy_cli/doctor

type
  FakeProbe = ref object
    outputs: Table[string, tuple[output: string; exitCode: int]]
    calls: seq[string]

proc fakeExec(fake: FakeProbe): DoctorExec =
  proc(command: string): tuple[output: string; exitCode: int] =
    fake.calls.add command
    fake.outputs.getOrDefault(command, ("", 1))

proc probe(target: DoctorTarget; fake: FakeProbe): DoctorProbe =
  DoctorProbe(target: target, exec: fake.fakeExec())

proc baseline(): FakeProbe =
  result = FakeProbe()
  result.outputs["nim --version"] = ("Nim Compiler Version 2.2.10\n", 0)
  result.outputs["node --version"] = ("v20.19.0\n", 0)
  result.outputs["npm --version"] = ("10.8.2\n", 0)

suite "viewy doctor":
  test "passes Linux checks with webkit2gtk 4.1":
    let fake = baseline()
    fake.outputs["pkg-config --version"] = ("1.9.5\n", 0)
    fake.outputs["pkg-config --exists gtk+-3.0 webkit2gtk-4.1"] = ("", 0)

    let result = runDoctor(probe(dtLinux, fake))

    check result.ok
    check result.output.contains("OK   Nim")
    check result.output.contains("OK   Node")
    check result.output.contains("WebKitGTK native")
    check result.output.contains("webkit2gtk-4.1")

  test "GTK4 webkitgtk 6 is lite-only and does not satisfy native Linux":
    let fake = baseline()
    fake.outputs["pkg-config --version"] = ("1.9.5\n", 0)
    fake.outputs["pkg-config --exists gtk4 webkitgtk-6.0"] = ("", 0)

    let result = runDoctor(probe(dtLinux, fake))

    check not result.ok
    check result.output.contains("FAIL WebKitGTK native")
    check result.output.contains("OK   WebKitGTK lite GTK4")
    check result.output.contains("webkitgtk-6.0")

  test "Linux webkit2gtk 4.0 is lite-only and does not satisfy native Linux":
    let fake = baseline()
    fake.outputs["pkg-config --version"] = ("1.9.5\n", 0)
    fake.outputs["pkg-config --exists gtk+-3.0 webkit2gtk-4.1"] = ("", 1)
    fake.outputs["pkg-config --exists gtk+-3.0 webkit2gtk-4.0"] = ("", 0)

    let result = runDoctor(probe(dtLinux, fake))

    check not result.ok
    check result.output.contains("FAIL WebKitGTK native")
    check result.output.contains("OK   WebKitGTK lite GTK3 fallback")
    check result.output.contains("webkit2gtk-4.0")

  test "fails with actionable Node version hint":
    let fake = baseline()
    fake.outputs["node --version"] = ("v20.18.1\n", 0)
    fake.outputs["xcode-select -p"] = ("/Library/Developer/CommandLineTools\n", 0)

    let result = runDoctor(probe(dtMacos, fake))

    check not result.ok
    check result.output.contains("FAIL Node")
    check result.output.contains("Upgrade to Node 20.19+ or 22.12+")

  test "fails with actionable Nim version hint":
    let fake = baseline()
    fake.outputs["nim --version"] = ("Nim Compiler Version 1.6.20\n", 0)
    fake.outputs["xcode-select -p"] = ("/Library/Developer/CommandLineTools\n", 0)

    let result = runDoctor(probe(dtMacos, fake))

    check not result.ok
    check result.output.contains("FAIL Nim")
    check result.output.contains("Upgrade to Nim 2.0+")

  test "fails when Linux pkg-config is missing":
    let fake = baseline()

    let result = runDoctor(probe(dtLinux, fake))

    check not result.ok
    check result.output.contains("FAIL pkg-config")
    check result.output.contains("Install pkg-config")

  test "passes macOS Xcode command line tools check":
    let fake = baseline()
    fake.outputs["xcode-select -p"] = ("/Library/Developer/CommandLineTools\n", 0)

    let result = runDoctor(probe(dtMacos, fake))

    check result.ok
    check result.output.contains("OK   Xcode CLT")

  test "passes Windows WebView2 runtime registry check":
    let fake = baseline()
    fake.outputs[
      "reg query HKLM\\Software\\WOW6432Node\\Microsoft\\EdgeUpdate\\Clients\\" &
        "{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5} /v pv"] = ("pv REG_SZ 123.0\n", 0)

    let result = runDoctor(probe(dtWindows, fake))

    check result.ok
    check result.output.contains("OK   WebView2 runtime")

  test "fails unsupported platforms":
    let fake = baseline()

    let result = runDoctor(probe(dtOther, fake))

    check not result.ok
    check result.output.contains("unsupported platform")
