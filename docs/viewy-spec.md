# viewy — A Tauri/Wails-Style Desktop App Framework for Nim

**Audience:** Claude Code agent implementing this project from scratch.
**Working name:** `viewy` (fits the treeform/treehouse `-y` naming aesthetic: pixie, boxy, zippy, jsony). Verify availability on nimble.directory before publishing; fallbacks: `glassy`, `paney`, `sashy`.

---

## 1. Mission

Build what Tauri is for Rust and Wails is for Go, but for Nim: a framework + CLI that lets developers ship small, fast desktop apps with a Nim backend and an HTML/CSS/JS frontend rendered in the OS-native webview (no bundled Chromium).

**v1 scope decisions (locked):**
- **Platforms:** Desktop only — Windows, macOS, Linux. No mobile, no browser-served mode.
- **Webview backend:** Pluggable backend abstraction; v1 ships exactly one backend wrapping the `webview/webview` C/C++ library (WebKitGTK on Linux, WKWebView/Cocoa on macOS, Edge WebView2 on Windows). The abstraction exists so a Wails-style direct-native backend can be added later without breaking user code.
- **Tooling:** Library + CLI with `init`, `dev`, `build`. **No** installer bundlers (dmg/msi/AppImage) and **no** TypeScript bindings generator in v1 — but the IPC protocol must be designed so TS bindgen is a pure additive feature later (Phase 4, stubbed).

## 2. Why existing Nim options don't suffice (context)

- `oskca/webview`, `drkameleon/nim-webview`: raw bindings to (old or new) webview/webview. No tooling, no IPC conventions, no asset pipeline.
- `nimview` (marcomq): closest prior art — webview + Jester webserver hybrid, supports browser/cloud mode. Different goals: it's a UI layer for Nim/C/Python, not a desktop app framework with dev-server workflow and embedded assets. Maintenance is sporadic.
- `neel`: Eel-style, runs a localhost webserver opened in a browser/window. Network-port-based; not the Wails "in-memory, no ports by default" model.

viewy's differentiation: **first-class CLI workflow (init/dev/build), Vite-native dev loop with HMR, compile-time embedded assets, typed RPC macro layer, zero-config single-binary output.**

## 3. Non-goals (v1)

- Mobile (iOS/Android), browser mode, cloud deployment.
- Installer/bundle generation (.dmg, .msi, .AppImage) — Phase 4+.
- TypeScript bindings codegen — Phase 4+ (but protocol must support it).
- Multi-webview-per-window, custom titlebars/frameless polish beyond what webview/webview exposes.
- Plugin system à la Tauri. Keep the core small.
- System tray, native menus (webview/webview doesn't expose these; document as known limitation tied to the backend, solvable by a future native backend).

## 4. Architecture

```
┌─────────────────────────────────────────────┐
│ CLI: viewy init | dev | build               │  (separate binary, nimble-installed)
├─────────────────────────────────────────────┤
│ viewy (library)                             │
│  ├─ app.nim        App/Window high-level API│
│  ├─ rpc.nim        expose macro, JSON codec │
│  ├─ events.nim     backend→JS event emit    │
│  ├─ assets.nim     embed / serve strategy   │
│  └─ backend/                                │
│      ├─ api.nim    Backend interface        │
│      └─ wv/        webview/webview backend  │
│          ├─ ffi.nim     hand-written C FFI  │
│          └─ backend.nim Backend impl        │
└─────────────────────────────────────────────┘
```

### 4.1 Backend abstraction (`backend/api.nim`)

Define a minimal interface every backend must satisfy. Use an object of refs to closures or a vtable-style object — NOT methods/inheritance (keep it ARC-friendly and `--mm:orc` clean):

```nim
type
  WindowHints* = enum whNone, whMin, whMax, whFixed

  Backend* = object
    create*: proc(debug: bool): BackendHandle
    destroy*: proc(h: BackendHandle)
    run*: proc(h: BackendHandle)            # blocks; main loop
    terminate*: proc(h: BackendHandle)
    dispatch*: proc(h: BackendHandle, fn: proc() {.gcsafe.})  # run on UI thread
    setTitle*: proc(h: BackendHandle, title: string)
    setSize*: proc(h: BackendHandle, w, h: int, hints: WindowHints)
    navigate*: proc(h: BackendHandle, url: string)
    setHtml*: proc(h: BackendHandle, html: string)
    eval*: proc(h: BackendHandle, js: string)
    init*: proc(h: BackendHandle, js: string)   # JS injected before page load
    bindFn*: proc(h: BackendHandle, name: string,
                  cb: proc(id, jsonArgs: string) {.gcsafe.})
    resolve*: proc(h: BackendHandle, id: string, ok: bool, jsonResult: string)
```

Everything above maps 1:1 onto the `webview_*` C API (`webview_create`, `webview_run`, `webview_dispatch`, `webview_bind`, `webview_return`, `webview_init`, `webview_eval`, `webview_set_html`, `webview_navigate`, `webview_set_size`, `webview_set_title`, `webview_terminate`, `webview_destroy`). That is intentional: backend #1 is a thin shim, and the API is small enough (~13 functions) that a future native backend implements the same surface.

### 4.2 FFI strategy

- **Hand-write the FFI** (`ffi.nim`). The webview C API is tiny; do not pull in futhark/c2nim as dependencies. Do not depend on the existing `oskca/webview` or `drkameleon/nim-webview` packages — vendor a **pinned release** of webview/webview instead (it has stable tagged releases now; pin in a `vendor/` dir or fetch at build time with checksum).
- Compile the amalgamated `webview.cc`/header via `{.compile.}` pragma with per-platform flags:
  - **Linux:** `pkg-config --cflags --libs gtk+-3.0 webkit2gtk-4.1` (fallback probe for `webkit2gtk-4.0`; optionally support `gtk4 webkitgtk-6.0` behind `-d:viewyGtk4`).
  - **macOS:** `-framework WebKit -framework Cocoa`, compile as Objective-C++.
  - **Windows:** MinGW-w64 or VCC; use webview's built-in WebView2 loader (`WEBVIEW_MSWEBVIEW2_BUILTIN_IMPL=1`) so no `WebView2Loader.dll` ships with the binary. Link `advapi32 ole32 shell32 shlwapi user32 version`. Requires C++14.
- All flags live in one module (`backend/lite/build.nim`) using `when defined(...)` + `gorge("pkg-config ...")` at compile time on Linux.

### 4.3 High-level user API (`app.nim`)

Target developer experience — a hello world must look like this:

```nim
import viewy

expose greet(name: string): string =
  "Hello, " & name & " from Nim!"

expose addTodo(t: Todo): seq[Todo] =      # object params via jsony
  todos.add t
  todos

var app = newApp(title = "My App", width = 1024, height = 768)
app.run()
```

- `newApp` reads embedded assets in release, dev-server URL in dev (see §4.5).
- `run()` registers all `expose`d procs via `bindFn`, then enters the loop.
- `emit(event: string, payload: T)` → serializes with jsony, `eval`s `window.__viewy.emit(...)` via `dispatch` (thread-safe: callable from worker threads).

### 4.4 RPC layer (`rpc.nim`)

- `expose` is a macro that:
  1. Registers proc name + a wrapper closure in a global registry (`{.global.}` seq populated at module init).
  2. Wrapper parses the JSON args array positionally, deserializes each param with **jsony** (treeform — fits the ecosystem and is fast), calls the proc, serializes the return.
  3. Errors: catch exceptions, return `{ "error": { "message", "type" } }` and reject the JS promise.
- Support sync procs in v1; `Future[T]` (chronos-free, std `asyncdispatch` optional) is Phase 3 — design the wrapper signature so async slots in (the webview bind/return model is already async-friendly: store `id`, call `resolve` later from `dispatch`).
- JS side: `webview_bind` already creates `window.<name>` returning a Promise. Add an injected `__viewy` runtime (via `init`) providing `viewy.call(name, ...args)`, `viewy.on(event, cb)`, `viewy.off`. Keep the injected JS < 2 KB, written as a string const in Nim (no JS build step for the runtime).
- **Protocol doc:** write `docs/protocol.md` specifying the JSON envelope (args array, result, error shape, event shape). TS bindgen later consumes the same registry via a `-d:viewyDumpBindings` compile mode that emits JSON metadata of exposed procs (names, param types, return types). Implement the dump mode in v1 (it's ~50 lines in the macro); the TS generator itself is Phase 4.

### 4.5 Asset strategy (`assets.nim`) — important, this is the subtle part

`webview/webview` has **no custom scheme handler** (unlike wry/WKURLSchemeHandler). Options ranked; implement A as default, B behind a flag:

- **A. Single-file injection (default, zero ports):** Production builds require the frontend to emit one self-contained `index.html` (CSS/JS inlined). The scaffold templates use `vite-plugin-singlefile`. The CLI build step embeds it via `staticRead` (through a generated `viewy_assets.nim`) and calls `setHtml`. No sockets, no temp files. Matches Wails' "no network ports" property. Limitation: very large apps and `fetch()` of relative assets need B.
- **B. Loopback micro-server (flag `assets = Served`):** Embed all of `dist/` into the binary (compile-time table: path → bytes, gzip-compressed with `zippy`). At startup, bind an `std/asynchttpdispatch`-based or hand-rolled HTTP/1.1 server on `127.0.0.1:0` (ephemeral port), require a per-launch random bearer token in a cookie set via injected JS, navigate the webview to it. Document the tradeoff honestly.
- **Dev mode:** neither — `navigate(devServerUrl)` (Vite, default `http://localhost:5173`), enabled by compiling with `-d:viewyDev=http://localhost:5173`.

### 4.6 Threading rules

- All backend calls except `dispatch` must happen on the main/UI thread. `emit` and `resolve` from other threads must route through `dispatch`. Enforce with an assertion in debug builds (store main thread id at `create`).
- Compile with `--mm:orc --threads:on` as the supported configuration; document it.

## 5. CLI (`viewy` binary)

Separate nimble package `viewy_cli` (or same repo, `bin = @["viewy"]`). Dependencies: std only + `parseopt`/`cligen` (prefer std `parseopt` to keep deps minimal) + `jsony` for config.

### `viewy init <name> [--template vanilla|svelte|react]`
- Scaffolds:
  ```
  myapp/
    viewy.json          # app config: title, size, assets mode, devUrl
    src/main.nim
    myapp.nimble
    frontend/           # vite project (template-specific)
    .gitignore
  ```
- Templates vendored in the CLI repo under `templates/` and copied (no network fetch). Each template's `vite.config` includes `vite-plugin-singlefile` for the prod build. Start with `vanilla`; svelte/react are stamped variants — implement vanilla first, others in Phase 3.

### `viewy dev`
- Spawns `npm run dev` (Vite) in `frontend/`, waits for the port to accept connections.
- Compiles and runs the Nim app with `-d:viewyDev=http://localhost:5173 --mm:orc --threads:on`; webview debug/devtools come from passing `debug=true` to the app/backend, not from `-d:debug`.
- Watches `src/**/*.nim` (use `std/os` polling watcher; no dep) → on change: rebuild, kill, relaunch the app process. Frontend changes are Vite HMR, no restart needed.
- Clean shutdown of both children on Ctrl-C.

### `viewy build [--release]`
- Runs `npm run build` in `frontend/` → expects `frontend/dist/index.html`.
- Generates `src/viewy_assets.nim` (staticRead of the single file, or the embedded table for Served mode).
- Compiles: `nim c -d:release --mm:orc --threads:on -d:strip --opt:size -o:build/myapp src/main.nim` plus platform link flags (the library's build.nim handles those automatically).
- macOS: also produce a minimal `MyApp.app` bundle structure (Info.plist + binary) — this is cheap and not an "installer", so it's in scope.
- Prints final binary size (the bragging metric: target < 3 MB for hello world).

### Config (`viewy.json`)
```json
{
  "name": "myapp",
  "title": "My App",
  "width": 1024, "height": 768, "resizable": true,
  "assets": "single",          // "single" | "served"
  "devUrl": "http://localhost:5173",
  "frontendDir": "frontend",
  "nimMain": "src/main.nim"
}
```

## 6. Repository layout (monorepo)

```
viewy/
  viewy.nimble            # the library
  src/viewy.nim           # re-exports
  src/viewy/{app,rpc,events,assets}.nim
  src/viewy/backend/{api.nim, wv/...}
  vendor/webview/         # pinned amalgamated webview source
  cli/                    # viewy_cli.nimble, bin
  cli/src/viewy_cli/templates/{vanilla,svelte,react}/
  examples/{hello,todo}/
  tests/
  docs/{protocol.md, architecture.md, limitations.md}
  .github/workflows/ci.yml
```

## 7. Phased plan with acceptance criteria

**Phase 1 — Core runtime (library only)**
1. FFI + wv backend compiles and opens a window on all three OSes (CI: ubuntu-latest, macos-latest, windows-latest; Linux CI uses xvfb).
2. `expose` macro round-trips: string, int, float, bool, seq, object params/returns via jsony.
3. `emit` from a worker thread reaches a JS listener.
4. Hello example: < 60 lines total, binary < 3 MB on Linux release.
- *Tests:* unit tests for the RPC envelope (pure, no window); a headless-skipped integration test that opens a window, calls an exposed proc via injected JS, asserts the result through a second bound fn.

**Phase 2 — Assets + CLI**
1. Single-file embed + `setHtml` path works in release.
2. Served mode with token auth works; `curl` without token → 401.
3. `viewy init/dev/build` end-to-end on the vanilla template; dev loop survives 10 consecutive backend edits.

**Phase 3 — DX polish**
1. Svelte + React templates.
2. Async exposed procs (`Future[T]`).
3. `viewy doctor` (checks nim, npm, pkg-config/webkit2gtk, WebView2 runtime).
4. `-d:viewyDumpBindings` JSON metadata emission (consumed by Phase 4).

**Phase 4 — Deferred (do not build now, keep doors open)**
- TS bindings generator from the dump metadata.
- Bundlers (dmg/msi/nsis/AppImage).
- Native backends (direct WebView2 COM / WKWebView / WebKitGTK) for menus, tray, multi-window, custom schemes.

## 8. Risks & mitigations

| Risk | Mitigation |
|---|---|
| webview/webview lacks custom schemes, menus, tray | Asset strategy A/B (§4.5); document limitations; backend abstraction enables native backend later |
| Windows MinGW vs VCC pain (C++14, WebView2 SDK) | Use built-in WebView2 loader; CI matrix covers both MinGW and VCC; document in README |
| Nim `--mm:orc` + threads + C callbacks (GC safety) | All callbacks `{.gcsafe.}`; route cross-thread work through `dispatch`; debug-mode thread assertions |
| Linux webkit2gtk version fragmentation (4.0/4.1/6.0) | pkg-config probe with clear error message; `-d:viewyGtk4` opt-in |
| Vite child-process management cross-platform | Use `osproc` with process groups; test Ctrl-C handling on all OSes |
| Name collisions on nimble | Check nimble.directory before first publish |

## 9. Conventions for the implementing agent

- Nim style: 2-space, `camelCase`, `result =` sparingly; run `nimpretty` in CI.
- Every public proc gets a doc comment; generate docs with `nim doc`.
- Pin everything: webview commit/tag, jsony, zippy versions in `.nimble`.
- Keep the dependency list ruthless: jsony, zippy (Served mode only). Nothing else in the library.
- Write `docs/limitations.md` honestly (no tray/menus/custom schemes in v1) — this prevents downstream surprise.
- Commit granularity: one phase-1 acceptance criterion per PR-sized commit.
