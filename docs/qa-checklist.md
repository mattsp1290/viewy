# Manual QA Checklist

This file is the named owner for Tier 3 manual QA. Automated CI owns Tier 1
pure logic and Tier 2 real-backend smoke tests; this checklist owns native UI
behavior that hosted CI cannot reliably observe, such as global menus, tray
status icons, desktop theme integration, and platform shell lifecycle.

Run these checks before closing a phase that adds or changes the listed surface.
Record the date, OS/version, package versions where relevant, commit SHA, and
result in the release notes or PR description for that phase.

## Linux Native Backend

Baseline:

- OS/session: GNOME or KDE desktop session, not only Xvfb.
- Packages: `gtk+-3.0`, `webkit2gtk-4.1 >= 2.40`, and
  `libayatana-appindicator3` at runtime when tray behavior is under test. The
  AppIndicator development package must not be required to compile the backend.
- Runtime capability: without AppIndicator installed, `newBackend().caps` omits
  `capTray` and tray slots remain nil instead of crashing during backend
  construction.
- Tray host: KDE has a visible SNI/AppIndicator host by default; GNOME tray
  tests require an enabled StatusNotifier/AppIndicator extension or equivalent
  host.
- Build: `nim c --mm:orc --threads:on -d:viewyBackend=native <app>.nim`.

Window lifecycle and IPC:

- Window opens, shows WebKit content, can be focused, resized, minimized, and
  closed through the window manager.
- `window.<name>(...args)` returns a Promise, resolves success values, rejects
  structured errors, and preserves `window.__viewy.call(name, ...args)`.
- Async RPC completion after navigation does not resolve an unrelated later
  page call.
- Worker-thread `emit`, deferred `resolve`, and terminate paths do not crash
  during repeated open/close cycles.

Custom scheme:

- `viewy://` production build loads `index.html`, CSS, JS, fonts, images, and
  nested assets without a loopback port.
- MIME types match browser expectations for HTML, JS, CSS, JSON, SVG, PNG,
  fonts, and unknown files.
- SPA fallback serves `index.html` for application routes and still returns 404
  for missing asset-like paths.
- Path traversal, encoded traversal, absolute paths, and backslashes are
  rejected.
- POST/request bodies and range requests work on a host with WebKitGTK >= 2.40.

Menus and accelerators:

- App/window menu renders with command, checkbox, radio, separator, submenu, and
  disabled states.
- Menu item activation dispatches the configured id exactly once.
- Checkbox and radio checked states display correctly and update after menu
  replacement.
- Accelerators fire for `CmdOrCtrl`, Shift, Alt/Option, function keys, and
  punctuation shortcuts without stealing text input unexpectedly.
- Context menus appear at the requested location and dispatch item ids.

Tray:

- Tray icon appears in GNOME/KDE with the configured icon and tooltip.
- Template/light-dark icon variants remain legible when the desktop theme
  changes.
- Tray menu renders nested items, separators, checkbox/radio state, and disabled
  state.
- Tray menu item activation dispatches the configured id exactly once.
- Show/hide/update/destroy operations do not leave stale tray icons.
- Quit-from-tray terminates the app cleanly after pending RPC/event handoffs.

Window events:

- Close, focus, blur, and resize events are delivered once per native event.
- Resize events report current width/height after manual drag and maximize.
- Event callbacks remain safe during close while worker-thread emits/resolves
  are pending.

## macOS Native Backend

Baseline:

- OS/session: interactive macOS desktop session.
- Build: `nim c --mm:orc --threads:on -d:viewyBackend=native <app>.nim`.
- Bundle: verify both direct binary launch and `.app` launch when bundle support
  is part of the phase.

Menus and accelerators:

- Main menu appears in the macOS menu bar with the expected app name.
- Standard app quit behavior works from the app menu and `Cmd+Q`.
- Command, checkbox, radio, separator, submenu, and disabled states render
  correctly.
- Accelerators fire with Command, Control, Option, Shift, function keys, and
  punctuation shortcuts.
- Menu updates preserve focus and do not leave stale items.

Tray/status item:

- Status item appears in the menu bar with correct regular and template icon
  rendering in light and dark modes.
- Status menu item activation dispatches ids exactly once.
- Updating and destroying the item leaves no stale menu-bar icon.
- Quit-from-tray/status item terminates cleanly after pending RPC/event
  handoffs, leaves no stale menu-bar icon, and leaves no lingering app process.

Window events:

- Close/focus/blur/resize events match macOS window behavior, including traffic
  light close and full-screen transitions when supported.
- Event callbacks remain safe during close while worker-thread emits/resolves
  are pending.

## Windows Native Backend

Baseline:

- OS/session: interactive Windows 11 desktop session with Evergreen WebView2
  runtime installed.
- Build: test MinGW and MSVC when both are supported by the phase.

Menus and accelerators:

- Native menu renders command, checkbox, radio, separator, submenu, and disabled
  states.
- Accelerators fire with Ctrl, Shift, Alt, function keys, and punctuation
  shortcuts.
- Menu item activation dispatches ids exactly once.
- Menu updates do not leave stale native handles or duplicate accelerators.

Tray:

- Notification-area icon appears with expected icon and tooltip.
- Light/dark icon variants remain legible when the Windows theme changes.
- Tray menu renders all item kinds and dispatches ids exactly once.
- Explorer restart or taskbar refresh does not permanently orphan the tray icon
  once the app updates or recreates it.
- Quit-from-tray terminates cleanly after pending RPC/event handoffs, leaves no
  stale notification-area icon, and leaves no lingering app process.

Window events:

- Close/focus/blur/resize events match native behavior, including Alt+F4 and
  taskbar close.
- DPI scaling changes do not corrupt resize dimensions or menu/tray placement.
- Event callbacks remain safe during close while worker-thread emits/resolves
  are pending.

## Release Gate

Before a release that changes native backend behavior:

- Tier 1 and Tier 2 automated tests are green on the supported matrix.
- Every checked platform above has a recorded manual QA result for the features
  touched by the release.
- Any unchecked item has a linked bead explaining the gap and why release can
  proceed.
