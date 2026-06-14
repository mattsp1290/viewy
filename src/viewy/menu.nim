## Shared native menu helpers.

import std/[strutils]

type
  AcceleratorParseError* = object of ValueError
    ## Raised when an accelerator string is malformed or unsupported.

  AcceleratorPlatform* = enum
    ## Target platform for platform-sensitive accelerator aliases.
    apMacOS
    apLinux
    apWindows

  AcceleratorModifier* = enum
    ## Backend-neutral modifier keys.
    amCtrl
    amShift
    amAlt
    amSuper

  Accelerator* = object
    ## Parsed accelerator shape consumed by native menu backends.
    modifiers*: set[AcceleratorModifier]
    key*: string

proc currentAcceleratorPlatform*(): AcceleratorPlatform =
  ## Return the compile-time host platform used by default native accelerators.
  when defined(macosx):
    apMacOS
  elif defined(windows):
    apWindows
  else:
    apLinux

proc parseFailure(value, reason: string): ref AcceleratorParseError =
  newException(AcceleratorParseError,
    "invalid accelerator " & value & ": " & reason)

proc normalizeKey(raw: string): string =
  let key = raw.strip()
  if key.len == 0:
    return ""

  let lower = key.toLowerAscii()
  case lower
  of "return":
    return "Enter"
  of "enter":
    return "Enter"
  of "esc", "escape":
    return "Escape"
  of "tab":
    return "Tab"
  of "space", "spacebar":
    return "Space"
  of "backspace":
    return "Backspace"
  of "delete", "del":
    return "Delete"
  of "insert", "ins":
    return "Insert"
  of "home":
    return "Home"
  of "end":
    return "End"
  of "pageup", "pgup":
    return "PageUp"
  of "pagedown", "pgdn":
    return "PageDown"
  of "up", "arrowup":
    return "Up"
  of "down", "arrowdown":
    return "Down"
  of "left", "arrowleft":
    return "Left"
  of "right", "arrowright":
    return "Right"
  of "plus":
    return "Plus"
  of "minus":
    return "Minus"
  of "comma":
    return "Comma"
  of "period", "dot":
    return "Period"
  of "slash":
    return "Slash"
  of "backslash":
    return "Backslash"
  of "semicolon":
    return "Semicolon"
  of "quote", "apostrophe":
    return "Quote"
  of "bracketleft", "leftbracket":
    return "BracketLeft"
  of "bracketright", "rightbracket":
    return "BracketRight"
  of "equal", "equals":
    return "Equal"
  of "grave", "backquote":
    return "Grave"
  else:
    discard

  if lower.len in 2 .. 3 and lower[0] == 'f':
    try:
      let n = lower[1 .. ^1].parseInt()
      if n in 1 .. 24:
        return "F" & $n
    except ValueError:
      discard

  if key.len == 1:
    let ch = key[0]
    if ch in {'a' .. 'z'}:
      return ($ch).toUpperAscii()
    if ch in {'A' .. 'Z', '0' .. '9'}:
      return $ch
    case ch
    of '-':
      return "Minus"
    of ',':
      return "Comma"
    of '.':
      return "Period"
    of '/':
      return "Slash"
    of '\\':
      return "Backslash"
    of ';':
      return "Semicolon"
    of '\'':
      return "Quote"
    of '[':
      return "BracketLeft"
    of ']':
      return "BracketRight"
    of '=':
      return "Equal"
    of '`':
      return "Grave"
    else:
      discard

  ""

proc parseAccelerator*(value: string;
    platform: AcceleratorPlatform): Accelerator =
  ## Parse a platform-agnostic accelerator string such as `CmdOrCtrl+Shift+P`.
  ##
  ## `CmdOrCtrl` maps to `amSuper` on macOS and `amCtrl` on Linux/Windows.
  ## Explicit `Cmd`/`Command` and `Super` tokens map to `amSuper` on every
  ## platform; explicit `Ctrl`/`Control` maps to `amCtrl`.
  let original = value
  let trimmed = value.strip()
  if trimmed.len == 0:
    raise parseFailure(original, "empty string")

  var keySeen = false
  for rawPart in trimmed.split('+'):
    let part = rawPart.strip()
    if part.len == 0:
      raise parseFailure(original, "empty segment")
    if keySeen:
      raise parseFailure(original, "key must be the final segment")

    let lower = part.toLowerAscii()
    var modifier: AcceleratorModifier
    var isModifier = true
    case lower
    of "cmdorctrl", "commandorcontrol":
      modifier =
        case platform
        of apMacOS: amSuper
        of apLinux, apWindows: amCtrl
    of "ctrl", "control":
      modifier = amCtrl
    of "shift":
      modifier = amShift
    of "alt", "option":
      modifier = amAlt
    of "cmd", "command", "super", "meta":
      modifier = amSuper
    else:
      isModifier = false

    if isModifier:
      if modifier in result.modifiers:
        raise parseFailure(original, "duplicate modifier " & part)
      result.modifiers.incl modifier
    else:
      result.key = normalizeKey(part)
      if result.key.len == 0:
        raise parseFailure(original, "unsupported key " & part)
      keySeen = true

  if not keySeen:
    raise parseFailure(original, "missing key")
  if result.modifiers.len == 0:
    raise parseFailure(original, "missing modifier")

proc parseAccelerator*(value: string): Accelerator =
  ## Parse an accelerator for the compile-time host platform.
  parseAccelerator(value, currentAcceleratorPlatform())
