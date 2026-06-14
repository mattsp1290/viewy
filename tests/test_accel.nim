import std/unittest

import viewy/menu

suite "accelerator parser":
  test "maps CmdOrCtrl per platform":
    let mac = parseAccelerator("CmdOrCtrl+Q", apMacOS)
    check mac.key == "Q"
    check mac.modifiers == {amSuper}

    let linux = parseAccelerator("CmdOrCtrl+Q", apLinux)
    check linux.key == "Q"
    check linux.modifiers == {amCtrl}

    let windows = parseAccelerator("CmdOrCtrl+Q", apWindows)
    check windows.key == "Q"
    check windows.modifiers == {amCtrl}

  test "parses explicit modifiers":
    let accel = parseAccelerator("Ctrl+Shift+Alt+Super+P", apLinux)
    check accel.key == "P"
    check accel.modifiers == {amCtrl, amShift, amAlt, amSuper}

  test "normalizes named keys and punctuation":
    check parseAccelerator("CmdOrCtrl+Enter", apMacOS).key == "Enter"
    check parseAccelerator("CmdOrCtrl+Esc", apMacOS).key == "Escape"
    check parseAccelerator("CmdOrCtrl+F12", apMacOS).key == "F12"
    check parseAccelerator("CmdOrCtrl+Plus", apMacOS).key == "Plus"
    check parseAccelerator("CmdOrCtrl+-", apMacOS).key == "Minus"
    check parseAccelerator("CmdOrCtrl+/", apMacOS).key == "Slash"

  test "rejects invalid strings":
    expect AcceleratorParseError:
      discard parseAccelerator("", apMacOS)
    expect AcceleratorParseError:
      discard parseAccelerator("CmdOrCtrl", apMacOS)
    expect AcceleratorParseError:
      discard parseAccelerator("Q", apMacOS)
    expect AcceleratorParseError:
      discard parseAccelerator("CmdOrCtrl++", apMacOS)
    expect AcceleratorParseError:
      discard parseAccelerator("CmdOrCtrl+Shift+Q+W", apMacOS)
    expect AcceleratorParseError:
      discard parseAccelerator("Shift+Shift+Q", apMacOS)
    expect AcceleratorParseError:
      discard parseAccelerator("CmdOrCtrl+UnknownKey", apMacOS)
