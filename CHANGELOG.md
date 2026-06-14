# Changelog

## 0.2.0 - Draft

Native-backend release:

- `-d:viewyBackend=native` is now the compile-time default backend selection on
  Linux, macOS, and Windows, and production scheme builds select native by
  default. Development mode still uses lite until the HMR follow-up lands. The
  previous vendored `webview/webview` backend remains available as
  `-d:viewyBackend=lite` for compatibility.
- New `viewy.json` files default to `assets = "scheme"`. Production scheme
  builds generate a multi-file asset table and load it through native custom
  scheme support when available, with lite falling back to served mode.
- Native scheme assets support normal URL-addressable frontend output through
  `viewy://` on Linux/macOS and the Windows `https://viewy.localhost/` virtual
  host mapping, including relative asset fetches, MIME inference, SPA document
  fallback, query strings, POST bodies, range handling, gzip metadata, and
  ETags.
- Native app/window menu-bar support is available through `capMenu`, with item
  id dispatch and accelerator handling. `capContextMenu` adds the
  backend-neutral context-menu API surface, but runtime platform implementations
  are still gated by follow-up backend work.
- Native system tray support is capability-gated by `capTray`, with icon,
  tooltip, menu dispatch, update, destroy, and start-hidden window workflows.
- Native window support expanded with macOS lifecycle events through
  `capWindowEvents` and show/hide helpers on native backends through
  `capWindowVisibility` for tray-first apps.
- Build and diagnostics support now includes native platform checks in
  `viewy doctor`, macOS bundle/ad-hoc codesign output, and Windows PerMonitorV2
  manifest behavior for native builds.
- Capability gating now separates compile-time backend selection from runtime
  platform availability so native-only features fail clearly when selected
  backend or host support is missing.

Release tag draft: `v0.2.0`.

## 0.1.0 - Draft

Initial pre-release of viewy:

- Nim runtime library for desktop apps backed by vendored `webview/webview`.
- CLI commands: `viewy init`, `viewy dev`, `viewy build`, and `viewy doctor`.
- Vanilla, React, and Svelte scaffold templates using Vite single-file builds.
- Single-file embedded assets and served asset mode.
- RPC macro support, event emission, async RPC completion, and binding metadata
  dump mode.
- CI coverage for Linux, macOS, Windows MinGW, and Windows VCC.

Release tag draft: `v0.1.0`.
