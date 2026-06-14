# Windows WebView2 COM Environment Spike

Issue: `viewy-2xh`

Timebox: 3 days.

Acceptance target: pure-Nim WebView2 environment creation succeeds on a clean
Windows 11 machine with only the Evergreen WebView2 runtime installed. If that
does not hold inside the timebox, the native backend keeps one C++ translation
unit for environment creation and uses hand-written Nim COM declarations after
that boundary.

## Finding

The pinned `Microsoft.Web.WebView2` SDK exposes environment creation as
`CreateCoreWebView2EnvironmentWithOptions`, exported by `WebView2Loader.dll`.
The Evergreen runtime supplies the browser runtime, but not a project-local SDK
loader DLL or a COM coclass that Nim can activate directly.

The existing vendored `webview/webview` implementation already contains a
builtin WebView2 loader path behind `WEBVIEW_MSWEBVIEW2_BUILTIN_IMPL=1`. That
path locates the installed runtime and calls the internal runtime entrypoint.
Reimplementing that loader in Nim would require duplicating the registry,
runtime-channel, DLL loading, and internal entrypoint handling from the C++
implementation before any backend COM work could start.

## Decision

Use the fallback: keep one retained C++ translation unit for WebView2
environment creation. The native backend should still use hand-written Nim COM
declarations for the minimal interface set once the environment pointer exists.

The fallback is recorded in
`src/viewy/backend/native/windows/webview2_env_spike.nim` and type-checked by
`tests/native/test_windows_webview2_env_spike.nim`.

The post-loader COM boundary is declared in
`src/viewy/backend/native/windows/com.nim`. That module is intentionally limited
to the WebView2 interfaces needed by the native backend and is compile-checked
separately from the loader fallback.

## Build Implications

The retained C++ loader path must use the same SDK pin as the lite backend:
`vendor/webview2/PIN`, exposed to Nim by
`viewy/backend/windows_webview2_pin.nim`.

Required C/C++ defines:

- `WEBVIEW_EDGE=1`
- `WEBVIEW_MSWEBVIEW2_BUILTIN_IMPL=1`
- `WEBVIEW_MSWEBVIEW2_EXPLICIT_LINK=1`

Required Windows libraries:

- `advapi32`
- `ole32`
- `shell32`
- `shlwapi`
- `user32`
- `version`

The fallback partially keeps the v1 shim model at the loader boundary only. It
does not reopen the backend API freeze and does not permit the native backend to
delegate menus, tray, asset scheme handling, or RPC behavior to `webview/webview`.
