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

## Windows fallback decision

Windows hosted runners are expected to provide the Edge WebView2 Runtime. If
the hosted runtime flakes or is unavailable, the fallback is a documented
`VIEWY_SKIP_WINDOWED=1` policy only for windowed integration tests, not for this
spike. This spike should remain red until either the hosted runner is fixed or a
self-hosted Windows runner/WebView2 bootstrap step is added and documented here.

Do not silently skip Windows window creation based on environment probing.
