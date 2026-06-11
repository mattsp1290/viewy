# Project Planning with Beads

## Agent Instructions

You are an expert software architect creating a comprehensive task breakdown. This task graph will be executed by AI agents working in parallel, coordinated through MCP Agent Mail with file reservations to prevent conflicts.

<quality_expectations>
Create a thorough, production-ready task graph. Include all necessary setup, implementation, testing, and documentation tasks. Go beyond the basics - consider edge cases, error handling, security considerations, and integration points. Each task should be specific enough for an agent to execute independently without ambiguity.
</quality_expectations>

## Project Information

### Links to Relevant Documentation

**Primary spec (read first):** `docs/viewy-spec.md` in this repo — the full architecture, API design, phased plan, and acceptance criteria.

**webview/webview (the C/C++ library being wrapped):**
- Repo / pinned tag 0.12.0: https://github.com/webview/webview (tags only — no release artifacts)
- At tag 0.12.0 the library is a SINGLE self-contained header (~4,560 lines, C API declarations + full implementation): https://github.com/webview/webview/blob/0.12.0/core/include/webview/webview.h — this is the FFI target. The `api.h`/`detail/` split and `scripts/amalgamate/amalgamate.py` exist only on master, NOT at 0.12.0; no amalgamation step is needed.
- Stub translation unit (what `{.compile.}` targets): https://github.com/webview/webview/blob/0.12.0/core/src/webview.cc — defining `WEBVIEW_HEADER` before include yields declaration-only mode; leaving it undefined compiles the implementation.
- WebView2 SDK — verified REQUIRED on Windows: `webview.h` unconditionally does `#include "WebView2.h"` under `WEBVIEW_EDGE` and the repo does not ship it (`WEBVIEW_MSWEBVIEW2_BUILTIN_IMPL` replaces only WebView2Loader.dll, not the SDK header): https://www.nuget.org/packages/Microsoft.Web.WebView2

**Nim dependencies:**
- jsony v1.1.6 (RPC JSON serialization): https://github.com/treeform/jsony
- zippy v0.10.19 (gzip for Served asset mode only): https://github.com/guzba/zippy
- Nim `{.compile.}` pragma: https://nim-lang.org/docs/manual.html#foreign-function-interface-compile-pragma
- `staticRead`: https://nim-lang.org/docs/system.html#staticRead,string
- ORC memory management: https://nim-lang.org/docs/mm.html
- std/osproc (CLI child-process management): https://nim-lang.org/docs/osproc.html

**Frontend tooling:**
- vite-plugin-singlefile v2.3.3 (compatible Vite 5–8): https://github.com/richardtallent/vite-plugin-singlefile
- Vite dev-server config (`port`, `strictPort`): https://vite.dev/config/server-options.html
- Vite build config (`assetsInlineLimit`): https://vite.dev/config/build-options.html
- Vite JS API (server-ready detection): https://vite.dev/guide/api-javascript.html
- Tauri's Vite integration (design reference for `viewy dev`): https://v2.tauri.app/start/frontend/vite/
- create-vite templates: https://github.com/vitejs/vite/tree/main/packages/create-vite

**Prior art (context for differentiation; all unmaintained or different goals):**
- https://github.com/oskca/webview (abandoned 2019)
- https://github.com/drkameleon/nim-webview (stale since 2022)
- https://github.com/marcomq/nimview (explicitly not in active development)
- https://github.com/Niminem/Neel (active but browser/WebSocket model, not webview)

**Verified corrections to the spec (source-verified against the 0.12.0 tag; these OVERRIDE the spec where they conflict):**
- **Vendoring (overrides §4.2's "amalgamated webview.cc" wording):** commit `vendor/webview/webview.h` (the single 0.12.0 header) plus a stub TU `vendor/webview/webview.cc` containing only `#include "webview.h"`. The `{.compile.}` pragma targets the `.cc` (you cannot `{.compile.}` a header) — compiled as Objective-C++ on macOS, C++14 on Windows. Record the pinned tag + sha256 of the header in `vendor/webview/PIN`, and commit webview's MIT license alongside.
- **Final v1 Backend vtable = spec §4.1 PLUS `unbind*: proc(h: BackendHandle, name: string)`** (`webview_unbind` exists since 0.11 and completes the RPC registry lifecycle). `webview_get_native_handle` and `webview_version` are deliberately NOT wrapped in v1.
- **`webview_return` contract (verified from the 0.12.0 doc comment):** status 0 resolves the JS promise, any non-zero value rejects it; `result` must be a valid JSON value or an empty string (which yields JS `undefined`). The Backend `resolve(id, ok, jsonResult)` proc maps `ok` → status 0/1.
- **WebView2 SDK vendoring bead must:** pin an exact Microsoft.Web.WebView2 NuGet version, enumerate the committed files (`build/native/include/WebView2.h` plus transitive includes such as `EventToken.h`), confirm MinGW-w64 compatibility, and commit Microsoft's license text.
- **Identifier/command fixes (the spec's incantations are copied verbatim into beads otherwise):** `-d:viewyDev:URL` is invalid Nim define syntax — use `-d:viewyDev=http://localhost:5173` consumed via `{.strdefine.}`. Drop `-d:debug` from `viewy dev` (debug is the default build mode; webview devtools come from passing `debug=true` to `create`). `std/asynchttpdispatch` (spec §4.5) does not exist — the module is `std/asynchttpserver`; whether to use it or a hand-rolled HTTP/1.1 server is decided in the Served-mode analysis bead.
- `WEBVIEW_MSWEBVIEW2_BUILTIN_IMPL` confirmed current at 0.12.0; defaults to 1 (and compile-enforces `WEBVIEW_MSWEBVIEW2_EXPLICIT_LINK=1`).
- Package name **viewy is available** on nimble (checked nim-lang/packages directly, 2026-06-11).
- vite-plugin-singlefile: `public/` assets are NOT inlined (templates must use `src/assets/`); SPA history routing breaks without HTTP — document in limitations.

### Project Description

Build **viewy** — what Tauri is for Rust and Wails is for Go, but for Nim: a framework + CLI that lets developers ship small, fast desktop apps with a Nim backend and an HTML/CSS/JS frontend rendered in the OS-native webview (no bundled Chromium).

The complete specification lives at `docs/viewy-spec.md` and is authoritative. Summary of locked v1 scope:

- **Platforms:** Desktop only — Windows, macOS, Linux.
- **Webview backend:** Pluggable backend abstraction (closure/vtable-based, not inheritance); v1 ships exactly one backend wrapping vendored webview/webview 0.12.0 (WebKitGTK on Linux, WKWebView on macOS, Edge WebView2 on Windows).
- **Library surface:** `newApp`/`run` high-level API, `expose` RPC macro (jsony positional-args JSON envelope, error envelope, promise rejection), thread-safe `emit` for backend→JS events via `dispatch`, injected `__viewy` JS runtime (< 2 KB, string const in Nim).
- **Asset strategy:** A (default) single-file `setHtml` embed via `staticRead` of a vite-plugin-singlefile build; B (flagged) loopback micro-server on `127.0.0.1:0` with per-launch bearer-token auth, zippy-compressed embedded table. Dev mode navigates to the Vite dev server.
- **CLI:** `viewy init` (vendored vanilla template first), `viewy dev` (Vite child + Nim rebuild/relaunch watcher, clean Ctrl-C), `viewy build` (singlefile build → generated `viewy_assets.nim` → release compile; macOS .app bundle structure; prints binary size).
- **Differentiation:** first-class init/dev/build workflow, Vite-native dev loop with HMR, compile-time embedded assets, typed RPC macro layer, zero-config single-binary output.
- **Non-goals (v1):** mobile, browser mode, installers (dmg/msi/AppImage), TS bindgen (but `-d:viewyDumpBindings` JSON metadata mode IS in scope), plugins, tray/menus (document as backend limitation).

Monorepo layout, phased plan (Phases 1–3 in scope, Phase 4 deferred-but-unblocked), risks, and per-phase acceptance criteria are in the spec §6–§8.

### Technical Stack

- **Nim** compiled with `--mm:orc --threads:on` (the supported configuration); 2-space camelCase style, nimpretty in CI.
- **Hand-written C FFI** to vendored webview/webview **0.12.0** (single header + stub `.cc` TU committed under `vendor/webview/`; pinned WebView2.h from the MS NuGet SDK vendored separately for Windows). Per-platform flags centralized in `backend/wv/build.nim`: pkg-config probe webkit2gtk-4.1→4.0 (gtk4/webkitgtk-6.0 behind `-d:viewyGtk4`) on Linux; `-framework WebKit -framework Cocoa` ObjC++ on macOS; built-in WebView2 loader + `advapi32 ole32 shell32 shlwapi user32 version`, C++14 on Windows (MinGW-w64 and VCC both in CI). The Linux probe must split pkg-config output into `{.passC.}`/`{.passL.}`, strip trailing newlines, fall back 4.1→4.0 in that order, fail with a clear `{.error: "install libwebkit2gtk-4.1-dev ...".}` when both probes miss, and be guarded by `when defined(linux)` (gorge runs on the build host; cross-compilation is documented as unsupported).
- **Library deps (ruthless):** jsony v1.1.6, zippy v0.10.19 (Served mode only). Nothing else.
- **CLI:** separate package in `cli/`, std `parseopt` + jsony for `viewy.json` config; child processes via std/osproc with process groups; std polling file watcher (no dep).
- **Frontend tooling:** Vite (port 5173, `strictPort: true`, `clearScreen: false`) + vite-plugin-singlefile v2.3.3; vanilla template first, svelte/react stamped variants in Phase 3. Node 20.19+/22.12+ floor.
- **CI:** GitHub Actions matrix — ubuntu-latest (xvfb), macos-latest, windows-latest (MinGW + VCC).

### Specific Requirements

- **Phase 1 acceptance (with mechanical verification spelled out — every bead description must carry its verification command):** window opens on all 3 OS runners in CI — the windowed integration test creates a window, schedules `terminate` via `dispatch` after its assertions (or a hard timeout), and must exit 0 under an outer watchdog (`timeout 120 ...`); it runs on ubuntu-latest under xvfb (where `DISPLAY` IS set, so it must NOT be skipped there), macos-latest, and windows-latest. Headless skip predicate is an explicit env var (`VIEWY_SKIP_WINDOWED=1`), never `DISPLAY` sniffing. An early CI-spike bead must prove webview windows actually open on hosted macOS/Windows runners before the test beads are written (WebView2 in CI sessions is historically flaky — if it fails, the fallback decision is documented, not improvised). `expose` round-trips string/int/float/bool/seq/object via jsony (pure unit tests, no window); `emit` from a worker thread reaches a JS listener; hello example < 60 lines (`wc -l` assertion in CI) and < 3 MB release binary on Linux (`stat` assertion in CI); injected `__viewy` JS runtime < 2 KB (unit-test assertion on the const's `len`).
- **Phase 2 acceptance:** single-file embed + `setHtml` works in release; Served mode requires a headless-startable server entry point (no webview window) so CI can assert `curl` without token → 401 on asset/RPC routes; `viewy init/dev/build` end-to-end on vanilla template; dev loop survives 10 consecutive backend edits via a scripted harness (edit file → await relaunch → assert process liveness), run in CI on Linux at minimum.
- **Phase 3:** svelte/react templates, async exposed procs (`Future[T]`, std asyncdispatch), `viewy doctor`. Note: `-d:viewyDumpBindings` is implemented ALONGSIDE the `expose` macro in Phase 1 (spec §4.4 — ~50 lines in the macro); Phase 3 only verifies/documents its JSON metadata format.
- **Phase 4 beads policy:** create ZERO Phase 4 beads (no TS bindgen, no bundlers, no native backends). "Deferred-but-unblocked" means the protocol doc and dump mode keep the door open — not that placeholder tasks exist.
- **Threading:** all backend calls except `dispatch` on the main/UI thread; `emit`/`resolve` from other threads route through `dispatch`; debug-build thread-id assertions; all C callbacks `{.gcsafe.}`. ORC reference counting is not atomic, so a closure allocated on a worker thread and executed on the UI thread is a use-after-free class of bug, not a `gcsafe` annotation issue — the task graph needs a dedicated design+implementation bead for the cross-thread handoff (serialize payloads to owned strings handed off via C-heap allocation or channels/`isolate`) plus a multi-thread `emit` stress-test bead.
- **Security:** Served mode bootstrap is two-step to avoid the chicken-and-egg (the injected-JS cookie can't authenticate the first navigation): the initial `navigate()` URL carries a one-time token as a query parameter valid only for the document route; injected JS exchanges it for the session cookie; all other routes (assets, RPC) require the cookie/bearer token and 401 without it. Bind to 127.0.0.1 only. RPC errors return structured `{ "error": { "message", "type" } }` envelope, never raw exceptions.
- **Protocol:** `docs/protocol.md` specifies the JSON envelope (positional args array, result, error shape, event shape) so TS bindgen is purely additive later.
- **Docs:** every public proc doc-commented (`nim doc` clean); `docs/architecture.md`; `docs/limitations.md` honest about no tray/menus/custom schemes, `public/` assets not inlined in single mode, SPA history routing caveat.
- **Pinning:** webview tag, jsony, zippy versions pinned in `.nimble`; verify `viewy` on nimble.directory before first publish (confirmed available 2026-06-11).
- **Commit granularity:** one Phase-1 acceptance criterion per PR-sized commit.

---

## Your Task

Analyze this project and create a comprehensive **Beads task graph** using the `bd` CLI. Beads provides dependency-aware, conflict-free task management for multi-agent execution.

---

<critical_constraint>
Your ONLY output is a bash shell script. Do NOT use `bd add` — the correct command to create a bead is `bd create`. Use `bd dep add` for dependencies. Do not implement anything yourself.
</critical_constraint>

## Output Format

Generate a shell script that creates the full task graph. The script should:

1. **Initialize Beads** (if not already initialized)
2. **Create all beads** with appropriate priorities
3. **Establish dependencies** between beads
4. **Add labels** for phase grouping

### Example Output

This fragment is format-only — it shows the expected script shape using real viewy tasks. The full graph must cover all phases per the spec.

```bash
#!/bin/bash
# Project: viewy
# Generated: 2026-06-11

set -e

# Initialize beads if needed
if [ ! -d ".beads" ]; then
    bd init
fi

echo "Creating project beads..."

# ========================================
# Phase 1: Core runtime (library only)
# ========================================

REPO_SCAFFOLD=$(bd create "Scaffold monorepo layout, viewy.nimble, nim.cfg, CI skeleton" \
  -d "Layout per spec §6. Root nim.cfg with --path:\"src\". Pin jsony 1.1.6, zippy 0.10.19. Reservation: /*.nimble, nim.cfg, .github/**" \
  -p 0 -l prep --silent)

VENDOR_WV=$(bd create "Vendor webview/webview 0.12.0 single header + stub TU" \
  -d "Commit vendor/webview/webview.h (0.12.0 tag) + webview.cc stub + MIT license + PIN file with tag/sha256. No amalgamation step at this tag. Reservation: vendor/webview/**" \
  -p 0 -l prep --silent)
bd dep add $VENDOR_WV $REPO_SCAFFOLD

CI_SPIKE=$(bd create "CI spike: prove webview window opens on all 3 hosted runners" \
  -d "Minimal create→dispatch(terminate)→exit-0 program under 'timeout 120'. ubuntu (xvfb), macos, windows (MinGW+VCC). Documents fallback if WebView2 fails in CI session. Verification: green matrix run." \
  -p 0 -l analysis --silent)
bd dep add $CI_SPIKE $VENDOR_WV

FFI=$(bd create "Hand-write ffi.nim against 0.12.0 C API incl. webview_unbind" \
  -d "Target vendor/webview/webview.h surface. webview_return: status 0 resolves, nonzero rejects, result must be valid JSON or empty string. Reservation: src/viewy/backend/wv/**" \
  -p 0 -l impl --silent)
bd dep add $FFI $VENDOR_WV

# ... continue for all phases ...

echo ""
echo "Bead graph created! View with:"
echo "  bd ready              # List unblocked tasks"
```

---

## Bead Creation Guidelines

### Priority Levels
- `-p 0` = Critical (blocking other work)
- `-p 1` = High (important but not blocking)
- `-p 2` = Medium (standard work)
- `-p 3` = Low (nice to have)

### Labels (authoritative taxonomy — use `-l`, no other values)
- `analysis` - Investigation/spike work (CI spike, Served-mode design, cross-thread handoff design)
- `prep` - Scaffolding, vendoring, pinning, config
- `impl` - Implementation (FFI, backend, RPC macro, assets, CLI, templates)
- `testing` - Unit/integration/stress tests and CI assertions
- `docs` - protocol.md, architecture.md, limitations.md, doc comments
- `cleanup` - Final polish, nimpretty, dead-code removal

### Dependency Rules
1. Never create cycles
2. Every bead should have a clear dependency chain back to setup tasks
3. Use `bd dep add CHILD PARENT` (child depends on parent completing first)
4. Parallel work should share a common ancestor, not depend on each other

### Task Granularity
- Each bead should be completable in **under 750 lines of code**
- Tasks should be atomic enough for one agent to complete without coordination
- If a task requires multiple file areas, consider splitting by file area

---

## File Reservation Planning

For each major work area, note the file patterns that will need exclusive reservation:

```bash
# Example reservation notes (add as bead descriptions)
# Auth work: src/auth/**, tests/auth/**, src/hooks/useAuth*
# API client: src/api/**, src/lib/fetch*, tests/api/**
# UI components: src/components/{ComponentName}/**, tests/components/{ComponentName}/**
```

This helps agents claim appropriate file surfaces when they start work.

---

## Context Documentation

Place any important context in `docs/` for agents to reference (the authoritative spec is already at `docs/viewy-spec.md`). This includes:
- Architecture decisions
- API documentation
- Design system specs
- External service integration guides

---

## Verification Steps

After generating the script:

1. **Run it**: `chmod +x setup-beads.sh && ./setup-beads.sh`
2. **Check ready work**: `bd ready` should show initial setup tasks

---

## Completeness Checklist

Ensure your task graph includes:

- [ ] All setup and configuration tasks
- [ ] Core architecture and shared utilities
- [ ] Feature implementation tasks (broken into small units)
- [ ] Error handling and edge cases
- [ ] Unit and integration tests for each feature
- [ ] API documentation
- [ ] Security considerations (input validation, auth checks)
- [ ] Performance considerations where relevant
- [ ] CI/CD and deployment tasks
- [ ] Clear dependency chains with no cycles
