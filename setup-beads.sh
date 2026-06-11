#!/bin/bash
# Project: viewy — Tauri/Wails-style desktop app framework for Nim
# Generated: 2026-06-11
# Source of truth: docs/viewy-spec.md + verified corrections in
# docs/prompts/tauri-wails-style-desktop-app-framework-for-nim.md
# Phases 1-3 only. Phase 4 beads are deliberately NOT created (policy:
# deferred-but-unblocked via protocol.md + dump mode, no placeholder tasks).

set -e

# Initialize beads if needed
if [ ! -d ".beads" ]; then
    bd init
fi

echo "Creating project beads..."

# ========================================
# Phase 1: Foundations (prep)
# ========================================

REPO_SCAFFOLD=$(bd create "Scaffold monorepo layout, viewy.nimble, nim.cfg, CI skeleton" \
  -d "Layout per spec §6: src/viewy.nim re-exports, src/viewy/{app,rpc,events,assets}.nim stubs, src/viewy/backend/{api.nim,wv/}, cli/, examples/, tests/, docs/, .github/workflows/ci.yml skeleton (ubuntu-latest with xvfb, macos-latest, windows-latest MinGW + VCC). Root nim.cfg with --path:\"src\" (committed — required for editor LSP). viewy.nimble pins jsony 1.1.6 and zippy 0.10.19 (zippy used by Served mode only); nothing else. Supported config --mm:orc --threads:on documented in README. 2-space camelCase, nimpretty target wired but not yet gating. Verification: nimble check exits 0; nim check --hints:off src/viewy.nim exits 0. Reservation: /*.nimble, nim.cfg, .gitignore, README.md, .github/**, src/** (stubs only)" \
  -p 0 -l prep -t task --silent)

VENDOR_WV=$(bd create "Vendor webview/webview 0.12.0 single header + stub TU + PIN + license" \
  -d "At tag 0.12.0 the library is ONE self-contained header (~4560 lines) — the api.h/detail/ split and amalgamate.py exist only on master; NO amalgamation step. Commit vendor/webview/webview.h from the 0.12.0 tag, plus stub TU vendor/webview/webview.cc containing only '#include \"webview.h\"' (the {.compile.} pragma targets the .cc — you cannot compile a header; leaving WEBVIEW_HEADER undefined compiles the implementation). Commit webview's MIT license alongside, and vendor/webview/PIN recording tag 0.12.0 + sha256 of the header. Verification: shasum -a 256 -c against PIN; file count and license present. Reservation: vendor/webview/**" \
  -p 0 -l prep -t task --silent)
bd dep add $VENDOR_WV $REPO_SCAFFOLD

VENDOR_WV2SDK=$(bd create "Vendor WebView2 SDK headers from pinned Microsoft NuGet package" \
  -d "webview.h unconditionally does #include \"WebView2.h\" under WEBVIEW_EDGE and the repo does not ship it (WEBVIEW_MSWEBVIEW2_BUILTIN_IMPL replaces only WebView2Loader.dll, not the SDK header). Pin an exact Microsoft.Web.WebView2 NuGet version; enumerate and commit the needed files (build/native/include/WebView2.h plus transitive includes such as EventToken.h); confirm MinGW-w64 compatibility of the committed headers; commit Microsoft's license text; record version + sha256 in a PIN file. Verification: a Windows compile of the stub TU with -DWEBVIEW_EDGE finds all includes under both MinGW-w64 and VCC. Reservation: vendor/webview2/**" \
  -p 0 -l prep -t task --silent)
bd dep add $VENDOR_WV2SDK $REPO_SCAFFOLD

BUILD_FLAGS=$(bd create "Implement backend/wv/build.nim per-platform compile/link flags" \
  -d "Single module centralizing all flags, guarded by when defined(...). Linux: gorge pkg-config probe webkit2gtk-4.1 then 4.0 (in that order), gtk4/webkitgtk-6.0 behind -d:viewyGtk4; split pkg-config output into {.passC.}/{.passL.}, strip trailing newlines, fail with clear {.error: \"install libwebkit2gtk-4.1-dev ...\".} when both probes miss; whole probe inside when defined(linux) (gorge runs on the build host; cross-compilation documented unsupported). macOS: -framework WebKit -framework Cocoa, compile TU as Objective-C++. Windows: WEBVIEW_MSWEBVIEW2_BUILTIN_IMPL (defaults to 1 at 0.12.0, compile-enforces WEBVIEW_MSWEBVIEW2_EXPLICIT_LINK=1), link advapi32 ole32 shell32 shlwapi user32 version, C++14, include path to vendored WebView2 SDK. {.compile.} targets vendor/webview/webview.cc. Verification: nim c compiles a create/destroy smoke program on the host OS. Reservation: src/viewy/backend/wv/build.nim" \
  -p 0 -l impl -t task --silent)
bd dep add $BUILD_FLAGS $VENDOR_WV
bd dep add $BUILD_FLAGS $VENDOR_WV2SDK

CI_SPIKE=$(bd create "CI spike: prove webview window opens on all 3 hosted runners" \
  -d "MUST land before any windowed-test beads are written. Minimal program: webview_create → dispatch-scheduled webview_terminate → exit 0, run under 'timeout 120' outer watchdog. Matrix: ubuntu-latest under xvfb (DISPLAY IS set there — must NOT skip), macos-latest, windows-latest (MinGW-w64 AND VCC). WebView2 in hosted CI sessions is historically flaky: if it fails, document the fallback decision (e.g. self-hosted runner, WebView2 runtime bootstrap step, or windows-windowed-skip policy) in docs/ci-notes.md — decided, not improvised. Verification: green matrix run on all 3 OSes, exit code 0 under the watchdog. Reservation: .github/workflows/**, tests/spike/**" \
  -p 0 -l analysis -t task --silent)
bd dep add $CI_SPIKE $BUILD_FLAGS

# ========================================
# Phase 1: Core runtime (library)
# ========================================

FFI=$(bd create "Hand-write ffi.nim against the 0.12.0 C API including webview_unbind" \
  -d "Hand-written FFI (no futhark/c2nim, no existing nim webview packages) for: webview_create, webview_destroy, webview_run, webview_terminate, webview_dispatch, webview_bind, webview_unbind, webview_return, webview_init, webview_eval, webview_set_html, webview_navigate, webview_set_size, webview_set_title. webview_get_native_handle and webview_version deliberately NOT wrapped in v1. webview_return contract (verified from 0.12.0 doc comment): status 0 resolves the JS promise, any non-zero rejects; result must be valid JSON or empty string (yields JS undefined). All C callback typedefs {.gcsafe, cdecl.}. Verification: nim check clean; compiles against vendored header via build.nim flags. Reservation: src/viewy/backend/wv/ffi.nim" \
  -p 0 -l impl -t task --silent)
bd dep add $FFI $VENDOR_WV

BACKEND_API=$(bd create "Define backend/api.nim Backend vtable interface + WindowHints" \
  -d "Spec §4.1 vtable object of proc fields (closures, NOT methods/inheritance; ARC/ORC-friendly): create, destroy, run, terminate, dispatch, setTitle, setSize, navigate, setHtml, eval, init, bindFn, resolve — PLUS unbind*: proc(h: BackendHandle, name: string) (verified correction: webview_unbind exists since 0.11 and completes the RPC registry lifecycle). WindowHints enum whNone/whMin/whMax/whFixed. resolve(id, ok, jsonResult) maps ok → webview_return status 0/1. Doc comment every field with its threading contract (all calls main-thread-only except dispatch). Verification: nim check clean; nim doc clean. Reservation: src/viewy/backend/api.nim" \
  -p 0 -l impl -t task --silent)
bd dep add $BACKEND_API $REPO_SCAFFOLD

WV_BACKEND=$(bd create "Implement wv backend.nim: vtable impl over ffi.nim" \
  -d "Construct the Backend vtable wired 1:1 onto the webview_* FFI, including unbind → webview_unbind and resolve(ok) → status 0/1. Store main thread id at create; debug-build assertions that every call except dispatch happens on the main/UI thread. All C callbacks {.gcsafe.}. The dispatch closure handoff uses a placeholder (direct call) until the cross-thread handoff bead lands — leave a TODO anchor for it. Verification: smoke program opens window, dispatch(terminate), exits 0 on host OS under timeout 120. Reservation: src/viewy/backend/wv/backend.nim" \
  -p 0 -l impl -t task --silent)
bd dep add $WV_BACKEND $FFI
bd dep add $WV_BACKEND $BACKEND_API
bd dep add $WV_BACKEND $BUILD_FLAGS

THREAD_DESIGN=$(bd create "Design cross-thread dispatch handoff (ORC non-atomic RC hazard)" \
  -d "ORC reference counting is NOT atomic: a closure allocated on a worker thread and executed on the UI thread is a use-after-free class of bug, not a gcsafe-annotation issue. Produce a short design doc (docs/threading.md) choosing the handoff mechanism: serialize payloads to owned strings handed off via C-heap allocation (allocShared) or channels/isolate; cover emit and resolve paths, ownership/free rules, and failure modes (dispatch after terminate). Acceptance: design reviewed against spec §4.6 rules; chosen mechanism implementable without new deps. Reservation: docs/threading.md" \
  -p 0 -l analysis -t task --silent)
bd dep add $THREAD_DESIGN $BACKEND_API

DISPATCH_IMPL=$(bd create "Implement thread-safe dispatch handoff per threading design" \
  -d "Implement the chosen mechanism from docs/threading.md in the wv backend: worker threads never touch GC-managed closures across the boundary; payloads serialized to owned strings via C-heap (allocShared + explicit free on UI thread) or channels/isolate. emit/resolve from non-main threads route through this path. Debug-build thread-id assertions retained. Verification: a unit-style program where a worker thread schedules 1000 dispatches while UI loop runs, exits 0 under valgrind/asan on Linux CI (or --mm:orc sanitizer-clean as available). Reservation: src/viewy/backend/wv/backend.nim (dispatch section), src/viewy/backend/wv/handoff.nim" \
  -p 0 -l impl -t task --silent)
bd dep add $DISPATCH_IMPL $THREAD_DESIGN
bd dep add $DISPATCH_IMPL $WV_BACKEND

JS_RUNTIME=$(bd create "Write injected __viewy JS runtime as Nim string const (< 2 KB)" \
  -d "String const in Nim (no JS build step), injected via backend init() before page load. Provides window.__viewy: call(name, ...args) wrapping the webview_bind-generated window.<name> promises, on(event, cb), off(event, cb), emit(event, payload) used by backend events.nim via eval. Must stay under 2048 bytes — enforced later by unit test. Keep it ES5-safe-ish for older WebKitGTK. Verification: const compiles; manual smoke in windowed test later. Reservation: src/viewy/runtime_js.nim" \
  -p 1 -l impl -t task --silent)
bd dep add $JS_RUNTIME $BACKEND_API

RPC_MACRO=$(bd create "Implement expose macro, RPC registry, jsony envelope + dump mode" \
  -d "rpc.nim per spec §4.4: expose macro registers proc name + wrapper closure in a global registry ({.global.} seq at module init). Wrapper parses JSON args array POSITIONALLY, deserializes each param with jsony, calls proc, serializes return with jsony. Errors: catch exceptions, return structured {\"error\":{\"message\",\"type\"}} envelope (never raw exception text leaks) and reject the JS promise via resolve(ok=false). Design wrapper signature so Future[T] slots in later (store id, resolve later from dispatch). ALSO implement -d:viewyDumpBindings in THIS bead (spec §4.4, ~50 lines in the macro): compile mode emitting JSON metadata of exposed procs (names, param types, return types) — Phase 3 only verifies/documents it. Verification: unit tests in the RPC test bead; nim check clean. Reservation: src/viewy/rpc.nim" \
  -p 0 -l impl -t task --silent)
bd dep add $RPC_MACRO $BACKEND_API

EVENTS=$(bd create "Implement events.nim: thread-safe emit(event, payload) backend→JS" \
  -d "emit serializes payload with jsony, evals window.__viewy.emit(event, payload) — ALWAYS routed through dispatch so it is callable from worker threads (uses the handoff mechanism, never raw closure capture across threads). Doc-comment the threading contract. Verification: unit test serializes envelope correctly (no window); worker-thread delivery covered by stress-test bead. Reservation: src/viewy/events.nim" \
  -p 1 -l impl -t task --silent)
bd dep add $EVENTS $DISPATCH_IMPL
bd dep add $EVENTS $JS_RUNTIME

APP=$(bd create "Implement app.nim: newApp/run high-level API wiring it all" \
  -d "newApp(title, width, height, resizable, assets mode, debug) constructs Backend, applies WindowHints; run() injects __viewy runtime via init(), registers all exposed procs from the RPC registry via bindFn, loads assets (setHtml embed in release / navigate to dev URL under -d:viewyDev — dev-mode define handled in its own bead), enters blocking run loop; clean destroy on exit. Hello-world DX target per spec §4.3 (expose + newApp + run, < 60 lines). Verification: hello example bead compiles and runs against this. Reservation: src/viewy/app.nim, src/viewy.nim" \
  -p 0 -l impl -t task --silent)
bd dep add $APP $WV_BACKEND
bd dep add $APP $RPC_MACRO
bd dep add $APP $JS_RUNTIME
bd dep add $APP $EVENTS

# ========================================
# Phase 1: Tests + example + docs
# ========================================

RPC_TESTS=$(bd create "Unit tests: RPC envelope round-trips + error envelope (no window)" \
  -d "Pure unit tests, no webview window: expose round-trips string, int, float, bool, seq, object params AND returns via jsony positional-args envelope. Error path: raising proc yields {\"error\":{\"message\",\"type\"}} envelope and ok=false. Also test -d:viewyDumpBindings emits parseable JSON metadata for a sample module. Verification: nimble test green on all 3 CI OSes (headless-safe). Reservation: tests/test_rpc.nim" \
  -p 0 -l testing -t task --silent)
bd dep add $RPC_TESTS $RPC_MACRO

RUNTIME_TESTS=$(bd create "Unit test: __viewy runtime const length < 2 KB" \
  -d "Assert viewyRuntimeJs.len < 2048 (Phase 1 acceptance: injected JS runtime < 2 KB, unit-test assertion on the const's len). Also sanity-assert it contains the call/on/off/emit entry points as substrings. Verification: nimble test green, headless. Reservation: tests/test_runtime_js.nim" \
  -p 1 -l testing -t task --silent)
bd dep add $RUNTIME_TESTS $JS_RUNTIME

WINDOWED_TEST=$(bd create "Windowed integration test: window + RPC via injected JS, all 3 OSes" \
  -d "Creates a window, calls an exposed proc via injected JS, asserts the result through a second bound fn, schedules terminate via dispatch after assertions (or hard timeout), must exit 0 under outer watchdog 'timeout 120 ...'. Runs on ubuntu-latest under xvfb (DISPLAY IS set there — must NOT be skipped), macos-latest, windows-latest. Headless skip predicate is the explicit env var VIEWY_SKIP_WINDOWED=1, NEVER DISPLAY sniffing. Follows whatever fallback the CI spike documented for WebView2 flakiness. Verification: green on all 3 runners in CI matrix. Reservation: tests/test_windowed.nim" \
  -p 0 -l testing -t task --silent)
bd dep add $WINDOWED_TEST $APP
bd dep add $WINDOWED_TEST $CI_SPIKE

EMIT_STRESS=$(bd create "Multi-thread emit stress test (cross-thread handoff soak)" \
  -d "Phase 1 acceptance: emit from a worker thread reaches a JS listener. Stress variant: N worker threads emit M events each through dispatch handoff while UI loop runs; JS listener counts and reports back via bound fn; assert no loss, no crash, no use-after-free (run under sanitizer on Linux where feasible). Honors VIEWY_SKIP_WINDOWED=1. Verification: exits 0 under 'timeout 120' on all 3 runners. Reservation: tests/test_emit_stress.nim" \
  -p 1 -l testing -t task --silent)
bd dep add $EMIT_STRESS $EVENTS
bd dep add $EMIT_STRESS $WINDOWED_TEST

HELLO=$(bd create "Hello example: < 60 lines, < 3 MB Linux release binary" \
  -d "examples/hello per spec §4.3 DX target: expose greet, newApp, run — under 60 lines TOTAL ('wc -l' CI assertion). Release build (nim c -d:release --mm:orc --threads:on -d:strip --opt:size) under 3 MB on Linux ('stat -c %s' CI assertion < 3145728). Verification commands live in CI bead; locally: wc -l examples/hello/src/main.nim and stat on the built binary. Reservation: examples/hello/**" \
  -p 1 -l impl -t task --silent)
bd dep add $HELLO $APP

TODO_EXAMPLE=$(bd create "Todo example: object params via jsony (expose addTodo)" \
  -d "examples/todo exercising object param/return (expose addTodo(t: Todo): seq[Todo] per spec §4.3), events (emit on change), and a small frontend. Serves as the realistic-app smoke for the RPC layer. Verification: compiles in CI; windowed run locally. Reservation: examples/todo/**" \
  -p 2 -l impl -t task --silent)
bd dep add $TODO_EXAMPLE $APP

CI_PHASE1=$(bd create "Wire Phase-1 CI gates: matrix, watchdogs, size/line assertions" \
  -d "Finalize .github/workflows/ci.yml: ubuntu-latest (xvfb-run for windowed tests), macos-latest, windows-latest (MinGW-w64 AND VCC jobs). Gates: nimble test (unit, headless), windowed + stress tests under 'timeout 120' watchdog with VIEWY_SKIP_WINDOWED honored only where the spike's fallback dictates, hello 'wc -l' < 60 assertion, Linux release 'stat -c %s' < 3145728 assertion, nimpretty --check (or diff-based check), nim doc clean. One Phase-1 acceptance criterion per PR-sized commit (convention reminder in CONTRIBUTING). Verification: full matrix green. Reservation: .github/workflows/**" \
  -p 0 -l testing -t task --silent)
bd dep add $CI_PHASE1 $WINDOWED_TEST
bd dep add $CI_PHASE1 $HELLO
bd dep add $CI_PHASE1 $RPC_TESTS
bd dep add $CI_PHASE1 $RUNTIME_TESTS
bd dep add $CI_PHASE1 $EMIT_STRESS

PROTOCOL_DOC=$(bd create "Write docs/protocol.md: JSON envelope spec (TS-bindgen-ready)" \
  -d "Specify the wire protocol so TS bindgen is purely additive later (Phase 4 door, no Phase 4 beads): positional args array, result encoding, error shape {\"error\":{\"message\",\"type\"}}, event shape for __viewy.emit, promise resolve/reject mapping to webview_return status 0/nonzero, and the -d:viewyDumpBindings metadata format reference. Verification: doc matches rpc.nim behavior (cross-checked against unit tests). Reservation: docs/protocol.md" \
  -p 1 -l docs -t task --silent)
bd dep add $PROTOCOL_DOC $RPC_MACRO

# ========================================
# Phase 2: Assets
# ========================================

ASSETS_SINGLE=$(bd create "Implement single-file asset mode: staticRead embed + setHtml" \
  -d "Default mode A (zero ports): assets.nim consumes a generated viewy_assets.nim that staticReads the vite-plugin-singlefile dist/index.html; newApp/run calls setHtml with it in release. Define the viewy_assets.nim generation contract here (CLI build bead generates it). Document limitation hooks: public/ assets NOT inlined by vite-plugin-singlefile (templates must use src/assets/), SPA history routing breaks without HTTP. Verification: release-built sample with embedded HTML opens and renders (windowed test bead). Reservation: src/viewy/assets.nim" \
  -p 0 -l impl -t task --silent)
bd dep add $ASSETS_SINGLE $APP

DEV_MODE=$(bd create "Implement dev-mode define: -d:viewyDev=URL via strdefine + navigate" \
  -d "Verified correction: -d:viewyDev:URL is INVALID Nim define syntax — use -d:viewyDev=http://localhost:5173 consumed via {.strdefine.}. When set, newApp/run navigates to the dev server URL instead of loading embedded assets; webview devtools come from passing debug=true to create (NOT -d:debug — debug build is already the default). Verification: unit test that the strdefine plumbs through (compile with the define, assert chosen URL); manual dev-loop run. Reservation: src/viewy/assets.nim (dev section), src/viewy/app.nim (touch point)" \
  -p 0 -l impl -t task --silent)
bd dep add $DEV_MODE $ASSETS_SINGLE

SINGLE_TEST=$(bd create "Test: single-file embed works in release build" \
  -d "Phase 2 acceptance 1: build a sample app with generated viewy_assets.nim in -d:release, open window, injected JS asserts the embedded DOM content arrived via setHtml, terminate via dispatch, exit 0 under 'timeout 120'. Honors VIEWY_SKIP_WINDOWED. Verification: green on CI matrix (Linux xvfb at minimum, ideally all 3). Reservation: tests/test_assets_single.nim" \
  -p 0 -l testing -t task --silent)
bd dep add $SINGLE_TEST $ASSETS_SINGLE

SERVED_ANALYSIS=$(bd create "Analysis: Served-mode server choice + two-step token bootstrap design" \
  -d "Decide std/asynchttpserver (NOTE: spec §4.5 names std/asynchttpdispatch which DOES NOT EXIST) vs hand-rolled HTTP/1.1 server — criteria: dep footprint (std only either way), threads+orc interaction with the UI loop, shutdown cleanliness. Design the two-step auth bootstrap solving the chicken-and-egg (injected-JS cookie can't authenticate the FIRST navigation): initial navigate() URL carries a one-time token as query param valid ONLY for the document route; injected JS exchanges it for the session cookie; all other routes (assets, RPC) require cookie/bearer and 401 without it. Bind 127.0.0.1 only, ephemeral port (127.0.0.1:0). Output: docs/served-mode.md design note. Reservation: docs/served-mode.md" \
  -p 1 -l analysis -t task --silent)
bd dep add $SERVED_ANALYSIS $APP

ASSETS_SERVED=$(bd create "Implement Served asset mode: loopback server, zippy table, token auth" \
  -d "Mode B behind assets=Served flag, per docs/served-mode.md: compile-time embedded table path→bytes gzip-compressed with zippy; server binds 127.0.0.1:0; per-launch random one-time token on the initial document URL, exchanged by injected JS for the session cookie; assets + RPC routes 401 without cookie/bearer; correct Content-Type and Content-Encoding: gzip handling. RPC errors stay in the structured error envelope, never raw exceptions. Must expose a headless-startable server entry point (no webview window) for CI testing. Verification: Served-mode test bead. Reservation: src/viewy/assets_served.nim, src/viewy/assets.nim (mode switch)" \
  -p 1 -l impl -t task --silent)
bd dep add $ASSETS_SERVED $SERVED_ANALYSIS

SERVED_TEST=$(bd create "Test: Served mode security — curl without token gets 401" \
  -d "Phase 2 acceptance 2, headless (uses the no-window server entry point so CI needs no display): start server; curl asset route and RPC route WITHOUT token → assert 401; with one-time token on document route → 200 + cookie; replayed one-time token → 401; with session cookie on assets/RPC → 200; server bound strictly to 127.0.0.1. Verification: scripted test green in CI on Linux at minimum. Reservation: tests/test_served_auth.nim, tests/served_harness/**" \
  -p 1 -l testing -t task --silent)
bd dep add $SERVED_TEST $ASSETS_SERVED

# ========================================
# Phase 2: CLI + template
# ========================================

CLI_SCAFFOLD=$(bd create "Scaffold cli/ package: parseopt dispatch + viewy.json config via jsony" \
  -d "Separate package in cli/ (bin viewy). std parseopt subcommand dispatch (init/dev/build, doctor slot for Phase 3), --help/--version. viewy.json config type per spec §5 (name, title, width, height, resizable, assets single|served, devUrl, frontendDir, nimMain) parsed with jsony; defaults + clear error on malformed config. Deps: std + jsony only. Verification: unit tests for config parse + arg dispatch; nimble build produces cli binary. Reservation: cli/** (excluding cli/templates/**)" \
  -p 0 -l impl -t task --silent)
bd dep add $CLI_SCAFFOLD $REPO_SCAFFOLD

TEMPLATE_VANILLA=$(bd create "Create vendored vanilla Vite template with vite-plugin-singlefile" \
  -d "cli/templates/vanilla: Vite project (vanilla-ts or vanilla-js per create-vite conventions), vite.config with vite-plugin-singlefile v2.3.3 (compatible Vite 5-8) for prod build, server config port 5173 + strictPort:true + clearScreen:false, assets under src/assets/ NOT public/ (public/ is not inlined by singlefile). Node 20.19+/22.12+ floor noted in template README. Includes viewy.json, src/main.nim using the library, .gitignore, *.nimble. No network fetch at init time — fully vendored. Verification: npm install && npm run build in the template yields a single self-contained dist/index.html. Reservation: cli/templates/vanilla/**" \
  -p 0 -l impl -t task --silent)
bd dep add $TEMPLATE_VANILLA $REPO_SCAFFOLD

CLI_INIT=$(bd create "Implement viewy init <name> [--template vanilla]" \
  -d "Copies the vendored template (no network), stamps project name into viewy.json/.nimble/package.json, refuses to overwrite an existing non-empty dir, prints next-steps. Template flag accepts vanilla only for now (svelte/react are Phase 3 — reject with clear message, not silent fallback). Verification: scripted test — init into temp dir, assert file tree, npm install && npm run build succeeds. Reservation: cli/src/init.nim, tests/cli/test_init.*" \
  -p 0 -l impl -t task --silent)
bd dep add $CLI_INIT $CLI_SCAFFOLD
bd dep add $CLI_INIT $TEMPLATE_VANILLA

CLI_DEV=$(bd create "Implement viewy dev: Vite child + Nim rebuild/relaunch watcher" \
  -d "Spawns npm run dev in frontendDir via std/osproc with process groups; waits for the dev port to accept connections (Vite port 5173 strictPort). Compiles and runs the app with -d:viewyDev=http://localhost:5173 --mm:orc --threads:on (VERIFIED: no -d:debug — debug is the default build mode; devtools come from debug=true to create; and the define uses = not :). Polling file watcher over src/**/*.nim (std only, no dep) → on change: rebuild, kill app process group, relaunch; Vite handles frontend HMR. Clean shutdown of BOTH children on Ctrl-C (signal handling cross-platform). Verification: dev-loop harness bead; manual smoke. Reservation: cli/src/dev.nim, cli/src/procutil.nim" \
  -p 0 -l impl -t task --silent)
bd dep add $CLI_DEV $CLI_INIT
bd dep add $CLI_DEV $DEV_MODE

CLI_BUILD=$(bd create "Implement viewy build [--release]: assets gen + release compile + .app" \
  -d "Runs npm run build in frontendDir, expects dist/index.html (singlefile); generates src/viewy_assets.nim per the contract in assets.nim bead (staticRead single file, or embedded gzip table for served mode); compiles nim c -d:release --mm:orc --threads:on -d:strip --opt:size -o:build/<name> (library build.nim supplies platform link flags automatically). macOS: also emit minimal <Name>.app bundle structure (Contents/Info.plist + MacOS/binary) — not an installer, in scope. Prints final binary size (target < 3 MB hello). Verification: e2e bead; locally build vanilla-template app and run the binary. Reservation: cli/src/build.nim, cli/src/assets_gen.nim" \
  -p 0 -l impl -t task --silent)
bd dep add $CLI_BUILD $CLI_INIT
bd dep add $CLI_BUILD $ASSETS_SINGLE

DEVLOOP_TEST=$(bd create "Test: dev loop survives 10 consecutive backend edits (scripted)" \
  -d "Phase 2 acceptance 3b: scripted harness — start viewy dev against an inited vanilla app, loop 10x: edit src/*.nim (touch a string literal), await relaunch (watch process table / readiness probe), assert app process liveness and responsiveness. Clean Ctrl-C at the end kills both children (assert no orphans). Runs in CI on Linux at minimum (xvfb). Verification: harness exits 0 in CI. Reservation: tests/cli/test_devloop.*" \
  -p 1 -l testing -t task --silent)
bd dep add $DEVLOOP_TEST $CLI_DEV

CLI_E2E=$(bd create "Test: viewy init/dev/build end-to-end on vanilla template" \
  -d "Phase 2 acceptance 3a: in CI — viewy init tmpapp → npm install → viewy build → assert build/<name> binary exists and runs (windowed where display available, else compile+size assertions); viewy dev smoke covered by dev-loop bead. macOS job also asserts .app bundle structure. Verification: green in CI matrix. Reservation: tests/cli/test_e2e.*" \
  -p 0 -l testing -t task --silent)
bd dep add $CLI_E2E $CLI_BUILD
bd dep add $CLI_E2E $CLI_DEV

# ========================================
# Phase 3: DX polish
# ========================================

TEMPLATE_SVELTE=$(bd create "Create svelte template (stamped variant of vanilla)" \
  -d "cli/templates/svelte: stamped variant keeping the same viewy.json/vite-plugin-singlefile/strictPort conventions as vanilla; assets under src/assets/. Enable --template svelte in init. Verification: init + npm run build yields single-file dist/index.html; scripted init test extended. Reservation: cli/templates/svelte/**" \
  -p 2 -l impl -t task --silent)
bd dep add $TEMPLATE_SVELTE $TEMPLATE_VANILLA
bd dep add $TEMPLATE_SVELTE $CLI_INIT

TEMPLATE_REACT=$(bd create "Create react template (stamped variant of vanilla)" \
  -d "cli/templates/react: stamped variant keeping the same viewy.json/vite-plugin-singlefile/strictPort conventions as vanilla; assets under src/assets/. Enable --template react in init. Verification: init + npm run build yields single-file dist/index.html; scripted init test extended. Reservation: cli/templates/react/**" \
  -p 2 -l impl -t task --silent)
bd dep add $TEMPLATE_REACT $TEMPLATE_VANILLA
bd dep add $TEMPLATE_REACT $CLI_INIT

TEMPLATES_TEST=$(bd create "Test: svelte + react templates build single-file output in CI" \
  -d "CI job: for each of svelte/react — viewy init --template X, npm install, npm run build, assert dist/index.html exists and is self-contained (no external script/link src references), viewy build produces a binary. Verification: green in CI on Linux at minimum. Reservation: tests/cli/test_templates.*" \
  -p 2 -l testing -t task --silent)
bd dep add $TEMPLATES_TEST $TEMPLATE_SVELTE
bd dep add $TEMPLATES_TEST $TEMPLATE_REACT

ASYNC_RPC=$(bd create "Implement async exposed procs: Future[T] via std asyncdispatch" \
  -d "Phase 3 acceptance 2: expose supports proc returning Future[T] (std asyncdispatch, chronos-free) — wrapper stores the bind id, awaits the future, calls resolve later through dispatch (the slot designed into the Phase-1 wrapper signature). Error in async path still yields the structured error envelope + promise rejection. Mind asyncdispatch pumping vs the blocking webview run loop — document the integration pattern chosen. Verification: async test bead. Reservation: src/viewy/rpc.nim (async section)" \
  -p 1 -l impl -t task --silent)
bd dep add $ASYNC_RPC $RPC_MACRO
bd dep add $ASYNC_RPC $DISPATCH_IMPL

ASYNC_TEST=$(bd create "Test: async exposed proc resolves/rejects JS promise correctly" \
  -d "Unit: async wrapper envelope + deferred resolve ordering (no window). Windowed: exposed Future[T] proc awaited from JS resolves with correct value; raising async proc rejects with error envelope. Honors VIEWY_SKIP_WINDOWED; 'timeout 120' watchdog. Verification: green in CI matrix. Reservation: tests/test_async_rpc.nim" \
  -p 1 -l testing -t task --silent)
bd dep add $ASYNC_TEST $ASYNC_RPC

DOCTOR=$(bd create "Implement viewy doctor: environment diagnostics" \
  -d "Phase 3 acceptance 3: checks and reports — nim present + version, npm/node present + Node 20.19+/22.12+ floor, Linux: pkg-config + webkit2gtk-4.1/4.0 probe result (mirrors build.nim logic), Windows: WebView2 runtime presence, macOS: Xcode CLT. Exit nonzero with actionable install hints when a required piece is missing. Verification: unit tests with mocked probe results; manual run on each OS in CI (informational job). Reservation: cli/src/doctor.nim" \
  -p 2 -l impl -t task --silent)
bd dep add $DOCTOR $CLI_SCAFFOLD

DUMP_VERIFY=$(bd create "Verify + document -d:viewyDumpBindings JSON metadata format" \
  -d "Phase 3 acceptance 4 (the dump mode itself shipped with the Phase-1 expose macro): golden-file test of the emitted JSON for a representative module (names, param types, return types, async flag); document the exact schema in docs/protocol.md so the Phase-4 TS generator is purely additive. NO TS generator work — Phase 4 has zero beads by policy. Verification: golden test green; protocol.md section reviewed. Reservation: tests/test_dump_bindings.nim, docs/protocol.md (dump section)" \
  -p 2 -l testing -t task --silent)
bd dep add $DUMP_VERIFY $RPC_MACRO
bd dep add $DUMP_VERIFY $PROTOCOL_DOC

# ========================================
# Docs + cleanup
# ========================================

ARCH_DOC=$(bd create "Write docs/architecture.md" \
  -d "Layered diagram + responsibilities per spec §4: CLI / library (app, rpc, events, assets) / backend abstraction / wv backend / vendored webview. Cover the vtable-not-inheritance decision, threading model (dispatch handoff, main-thread rule), asset modes A/B, dev-mode define, and why FFI is hand-written against a pinned tag. Verification: reviewed against shipped code; links resolve. Reservation: docs/architecture.md" \
  -p 2 -l docs -t task --silent)
bd dep add $ARCH_DOC $APP

LIMITS_DOC=$(bd create "Write docs/limitations.md (honest)" \
  -d "No system tray, no native menus, no custom URL schemes (webview/webview backend limitation; future native backend could solve — but Phase 4 has no beads). public/ assets NOT inlined in single-file mode (use src/assets/). SPA history routing breaks without HTTP — use hash routing or Served mode. Cross-compilation unsupported (gorge probes run on build host). webview_get_native_handle/webview_version not wrapped in v1. Served-mode tradeoffs (ports, token model). Verification: every claim cross-checked against implementation. Reservation: docs/limitations.md" \
  -p 2 -l docs -t task --silent)
bd dep add $LIMITS_DOC $ASSETS_SINGLE
bd dep add $LIMITS_DOC $SERVED_ANALYSIS

DOC_COMMENTS=$(bd create "Doc-comment every public proc; nim doc clean in CI" \
  -d "Sweep all public surface (app, rpc, events, assets, backend/api, runtime const): every public proc gets a doc comment per spec §9; nim doc runs clean and is added as a CI gate (in the CI workflow file's docs job). Verification: nim doc --project src/viewy.nim exits 0 with no missing-doc warnings per chosen lint level. Reservation: src/** (doc comments only), .github/workflows/ (docs job)" \
  -p 2 -l docs -t task --silent)
bd dep add $DOC_COMMENTS $APP
bd dep add $DOC_COMMENTS $EVENTS
bd dep add $DOC_COMMENTS $ASSETS_SINGLE
bd dep add $DOC_COMMENTS $ASSETS_SERVED

CLEANUP=$(bd create "Final polish: nimpretty sweep, dead code removal, TODO triage" \
  -d "nimpretty across src/ cli/ tests/ examples/ (2-space camelCase per spec §9) and make the CI check gating; remove dead code and stale TODO anchors (especially the pre-handoff dispatch placeholder); confirm dependency list is still ruthless (jsony, zippy only). Verification: nimpretty --check clean in CI; grep for TODO anchors returns only intentional ones. Reservation: repo-wide formatting pass (coordinate: run when no other bead is in flight)" \
  -p 3 -l cleanup -t chore --silent)
bd dep add $CLEANUP $CI_PHASE1
bd dep add $CLEANUP $CLI_E2E
bd dep add $CLEANUP $TEMPLATES_TEST

PUBLISH_PREP=$(bd create "Nimble publish prep: pins verified, name check, release checklist" \
  -d "Verify webview tag, jsony 1.1.6, zippy 0.10.19 pinned in .nimble files; 'viewy' confirmed available on nimble (checked nim-lang/packages 2026-06-11 — re-verify at publish time); nimble check clean for both packages; README quickstart matches actual CLI behavior; tag + changelog draft. Verification: nimble check exit 0; dry-run install from a clean clone. Reservation: *.nimble, README.md, CHANGELOG.md" \
  -p 2 -l cleanup -t chore --silent)
bd dep add $PUBLISH_PREP $CLEANUP
bd dep add $PUBLISH_PREP $DOC_COMMENTS
bd dep add $PUBLISH_PREP $LIMITS_DOC
bd dep add $PUBLISH_PREP $ARCH_DOC
bd dep add $PUBLISH_PREP $DUMP_VERIFY

echo ""
echo "Bead graph created! View with:"
echo "  bd ready              # List unblocked tasks"
echo "  bd dep tree           # Show dependency tree"
echo "  bd dep cycles         # Verify no cycles"
