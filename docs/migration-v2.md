# Migrating from v1 to v2

viewy v2 keeps the v1 programming model, but it is not a zero-behavior-change
release. The migration contract is scoped:

- A v1 app rebuilt with `-d:viewyBackend=lite` keeps the v1 backend behavior.
- A v1 app rebuilt on the native backend should build without source edits, but
  asset loading semantics change when the app uses the new scheme asset mode.

## What Changes

v2 changes two defaults:

- Backend selection moves from the old `wv` webview backend to `native`.
- New `viewy.json` files default from `assets = "single"` to
  `assets = "scheme"`.

The old backend is now named `lite`. It is the compatibility backend backed by
`webview/webview`. The old import path still exists as a deprecated shim:

```nim
import viewy/backend/wv/backend
```

New code should import:

```nim
import viewy/backend/lite/backend
```

Most applications should not import either backend module directly. Use
`import viewy` and select a backend at compile time.

## Compatibility Mode

To preserve v1 behavior, compile with the lite backend:

```bash
nim c --mm:orc --threads:on -d:viewyBackend=lite src/main.nim
```

This keeps the v1 window/webview behavior and the v1 asset behavior when paired
with legacy asset modes. This is the rollback path used by the CI gate.

## Native Backend Mode

To use the native backend:

```bash
nim c --mm:orc --threads:on -d:viewyBackend=native src/main.nim
```

Native backend work is staged by platform. Native builds expose capabilities
through backend feature flags; APIs that require unavailable native features
fail at compile time or at runtime capability checks instead of silently
falling back.

At this stage, `-d:viewyBackend=native` is implemented for Linux, macOS, and
Windows. Use `-d:viewyBackend=lite` only when you need the compatibility
backend. Production `scheme` builds select native on supported platforms;
`viewy dev` still uses lite until the native HMR follow-up lands.

Windows native status:

- `capScheme`, IPC/init-script parity, app/window menus, tray menus, and
  show/hide window visibility are implemented on the Win32/WebView2 backend.
- Production `viewy://app/...` scheme navigations are mapped internally to
  `https://viewy.localhost/...` because WebView2 serves virtual-host requests
  more reliably than custom schemes.
- Windows native builds need the Microsoft Edge WebView2 Evergreen Runtime at
  runtime. The WebView2 SDK/COM ABI is vendored and pinned in the repository.
- `capWindowEvents` is still macOS-only, and context-menu APIs are staged but
  not advertised by any native backend at runtime yet.

## Asset Mode Mapping

`viewy.json` accepts these asset values:

| `viewy.json` value | Runtime mode | Compatibility behavior |
| --- | --- | --- |
| `scheme` | `assetsScheme` | New default. Generates a multi-file asset table. Native backends serve it through a custom scheme when supported; lite uses the served-mode loopback fallback. |
| `single` | `assetsEmbedded` | Legacy v1 single-file HTML path. Loads one generated document with `setHtml`. |
| `served` | `assetsServedMode` | Legacy v1 loopback HTTP path. Starts an authenticated localhost server for generated assets. |

The important migration detail is that `scheme` is not the same behavior as
v1 `single`. Scheme mode preserves a multi-file frontend output and serves
assets by URL. Single-file mode embeds one HTML document.

## Choosing a Migration Path

Use `assets = "single"` and `-d:viewyBackend=lite` when you need the closest
v1 behavior during the transition.

Use `assets = "scheme"` when your frontend expects normal URL-addressable
files, relative `fetch()` calls, or a multi-file Vite output. On backends with
scheme support this avoids the loopback HTTP server. On lite, it uses the
served-mode fallback.

Use `assets = "served"` only when you specifically want the legacy loopback
HTTP behavior.

## Behavior Differences to Audit

Before switching an existing app to native/scheme mode, check:

- Frontend asset URLs: scheme mode keeps separate files, while single mode
  relies on a single generated HTML document.
- SPA routing: single mode has no server to answer deep links. Scheme and
  served modes route through an asset handler/server.
- Local ports: served mode opens a loopback port; native scheme mode does not.
- Native features: menus, tray, custom schemes, and window lifecycle events are
  capability-gated and vary by platform while v2 native work lands.
- Direct backend imports: replace `viewy/backend/wv/backend` with
  `viewy/backend/lite/backend`, or remove direct backend imports and use
  `import viewy`.

## Current Build Notes

The CLI maps `viewy.json` asset values through the runtime asset modes above.
Production `scheme` builds select the native backend on Linux, macOS, and
Windows. Legacy `single` and `served` builds continue to select lite for v1
compatibility.

This staged behavior lets existing apps keep shipping while native backends
continue to gain platform-specific menu, tray, context-menu, and lifecycle
coverage.
