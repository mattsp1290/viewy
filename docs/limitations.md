# Limitations

viewy keeps a small compatibility backend and is adding native backends in v2.
This document lists current limitations so users can choose the right backend
and asset mode without assuming platform features that are not implemented.

For v1-to-v2 behavior changes, see [migration-v2.md](migration-v2.md).

## Native Desktop Features

The lite backend does not expose:

- system tray icons;
- native menu bars or context menus;
- custom URL scheme handlers;
- direct native handles;
- the linked `webview/webview` version at runtime.

The backend abstraction is deliberately narrow. The lite backend
wraps create/run/destroy, title, size, navigation, HTML injection, JavaScript
eval/init, binding, unbinding, and promise return. It intentionally does not
wrap `webview_get_native_handle` or `webview_version`, and there is no API for
tray, native menus, or custom schemes.

These are lite-backend limitations, not permanent product goals. Native
backends add deeper platform integration behind capability gates as each
platform implementation lands.

## Asset Modes

Scheme mode is the default asset value for new `viewy.json` files. It generates
an embedded multi-file `dist/` asset table. Native backends serve that table
through a custom scheme when supported. The lite backend cannot register a
native custom scheme, so scheme mode uses the served-mode loopback fallback on
lite.

Single-file mode is the legacy `assets = "single"` path. It embeds one generated
HTML document and loads it with `setHtml`. It uses no port, no temp directory,
and no local HTTP server.

That also means single-file mode behaves like one static document:

- Vite `public/` files are copied as separate files and are not inlined into
  the generated HTML. Put imported assets under `src/assets/`, or use served
  mode when separate files must remain separate.
- Browser history routing does not have an HTTP server to answer deep links.
  Use hash routing. Served mode can serve separate files, but it does not
  currently fall back to `index.html` for arbitrary SPA routes.
- Relative `fetch()` calls for files next to the document are not a good fit.
  Use served mode if the frontend expects URL-addressable files.

Served mode is the legacy `assets = "served"` path. It embeds the built `dist/`
tree as gzip-compressed assets and starts a loopback-only HTTP server bound to
`127.0.0.1` on an ephemeral port. It solves separate URL-addressable asset
files, but it has real tradeoffs:

- the app owns a local HTTP port for the process lifetime;
- the initial document URL carries a one-time token;
- subsequent asset requests authenticate with a per-launch session cookie or
  bearer token;
- asset responses are protected with `Cache-Control: no-store`;
- unknown paths return `404` rather than falling back to the document route;
- HTTP-backed RPC is not implemented; runtime RPC still uses webview bindings.

## Build Portability

Cross-compilation is not supported. The lite backend selects and probes
platform dependencies at Nim compile time on the build host. On Linux, the build
module runs `pkg-config` through `gorge` to find GTK/WebKitGTK flags, so the
host must have the target platform development packages installed and runnable.

Build on the operating system you are targeting:

- Linux: GTK and WebKitGTK development packages;
- macOS: system WebKit and Cocoa frameworks;
- Windows: MinGW-w64 or MSVC with WebView2 support.

The CI matrix builds and runs windowed lite and native tests on Linux, macOS,
Windows MinGW, and Windows MSVC. Other compiler/platform combinations are not
part of the supported surface.

## Runtime Scope

viewy is desktop-only. There is no mobile backend, no browser-hosted mode, no
installer generator, and no TypeScript binding generator in v1. The RPC metadata
dump exists for tooling, but generated TypeScript bindings are future work.

The supported Nim configuration is:

```bash
nim c --mm:orc --threads:on
```

Other memory managers and non-threaded builds are not tested. Cross-thread
backend-to-JavaScript events and deferred RPC resolution use typed unmanaged
handoffs; generic closure dispatch is for UI-thread-created work.

## Verified Against

These statements are based on the current implementation:

- [src/viewy/backend/lite/ffi.nim](../src/viewy/backend/lite/ffi.nim)
  wraps the v1 `webview/webview` C API subset and explicitly omits native handle
  and version helpers.
- [src/viewy/assets.nim](../src/viewy/assets.nim)
  documents the single-file generated asset contract and its `public/` and
  history-routing caveats.
- [src/viewy/assets_served.nim](../src/viewy/assets_served.nim)
  implements the loopback server, per-launch prefix, one-time document token,
  session token, cookie/bearer authentication, and no-store asset responses.
- [src/viewy/backend/lite/build.nim](../src/viewy/backend/lite/build.nim)
  performs host compile-time platform selection and Linux `pkg-config` probes.
- [src/viewy/app.nim](../src/viewy/app.nim)
  wires served mode as static asset navigation while RPC remains webview
  binding based.
