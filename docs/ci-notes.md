# CI notes

## Window smoke spike

The Phase 1 window spike runs `tests/spike/window_smoke.nim` on the GitHub
Actions hosted matrix:

- `ubuntu-latest` under `xvfb-run`;
- `macos-latest`;
- `windows-latest` with MinGW-w64;
- `windows-latest` with VCC.

The smoke is intentionally minimal: create the webview, schedule termination via
the backend's typed dispatch handoff, enter the native event loop, and destroy
the handle after `run` returns. Each lane runs the binary under a 120-second
Python watchdog. Linux installs `libgtk-3-dev` and `libwebkit2gtk-4.1-dev`; the
workflow must not skip because `DISPLAY` is present under Xvfb.

## Linux tray gap

GitHub-hosted Linux runners do not provide a StatusNotifierItem/AppIndicator
host. CI can verify the native Linux backend's AppIndicator soft-dependency
probe, including graceful omission of `capTray` when the runtime library is
unavailable. It cannot verify tray create/update/destroy against a real shell
host, or the positive shell integration path where the tray icon is visible,
the user opens the tray menu, and menu item activation dispatches ids.

Treat that visible-tray path as manual QA owned by
[docs/qa-checklist.md](qa-checklist.md). Run it in KDE or in GNOME with an
enabled StatusNotifier/AppIndicator extension before releasing Linux tray
changes.

## Windows fallback decision

Windows hosted runners are expected to provide the Edge WebView2 Runtime. If
the hosted runtime flakes or is unavailable, the fallback is a documented
`VIEWY_SKIP_WINDOWED=1` policy only for windowed integration tests, not for this
spike. This spike should remain red until either the hosted runner is fixed or a
self-hosted Windows runner/WebView2 bootstrap step is added and documented here.

Do not silently skip Windows window creation based on environment probing.

GitHub-hosted Windows runners do not replace the clean Windows 11
Evergreen-only VM release gate in [docs/qa-checklist.md](qa-checklist.md).
That gate verifies the native scheme smoke and Tier 2 native windowed suite on a
machine without developer SDK assumptions.
