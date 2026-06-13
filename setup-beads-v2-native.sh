#!/bin/bash
# Project: viewy
# Change: viewy v2 — native backends (custom schemes, native menus, system tray)
# Type: MIGRATION (wv shim -> Wails-style direct native backends) + NEW_FEATURE
# Generated: 2026-06-13
# Source of truth: docs/prompts/viewy-v2-native-backends.md (+ verified codebase grounding)
#
# Grounding notes (verified against the tree, not assumed):
#  - Backend is a 16-slot closure-vtable in src/viewy/backend/api.nim (no caps/menu/tray types yet).
#  - No backend-selection seam exists: src/viewy/app.nim:7 hard-imports viewy/backend/wv/backend;
#    backends are runtime-injected via newApp(backend=...). There is NO viewyBackend strdefine and NO select.nim.
#  - dispatchTerminate is a MODULE export of wv/backend.nim + wv/handoff.nim (NOT a vtable slot);
#    called by tests test_windowed/test_async_rpc/test_wv_handoff/test_wv_teardown/test_emit_stress/test_assets_single
#    and the three CLI templates.
#  - Two AssetMode enums: cli/.../config.nim {amSingle="single", amServed="served"} default amSingle,
#    and src/viewy/assets.nim {assetsEmbedded, assetsServedMode, assetsDevServer}.
#  - events.nim is backend->JS emit only (emitScript/emit). No App.on / WindowEvent today.
#  - assets_served.nim owns normalizeAssetPath + the loopback auth (__viewy_session cookie, Bearer token,
#    rewriteAbsoluteAssetUrls) that scheme mode must retire.
#  - CI: 4-way matrix (ubuntu+gcc, macos+clang, windows+mingw, windows+vcc); xvfb Linux only; NO valgrind;
#    apt installs libwebkit2gtk-4.1-dev (unversioned); 3 MiB binary-size assert; 120s windowed watchdog;
#    windowed tests gated by VIEWY_SKIP_WINDOWED=1.
#  - vendor/webview2/PIN = Microsoft.Web.WebView2 1.0.4022.49; vendor/webview/PIN = webview/webview 0.12.0.
#  - Both nimbles are 0.1.0; CHANGELOG top is "0.1.0 - Draft".

set -e

# Initialize beads if needed (already initialized in this repo; guard kept for portability).
if [ ! -d ".beads" ]; then
    bd init
fi

echo "Creating viewy v2 native-backend beads..."

# ============================================================================
# PHASE 0 — v2 interface + asset-pipeline groundwork (NO native code)
#   Foundations everything else depends on. All design "§decisions" resolve here.
# ============================================================================

EXTEND_API=$(bd create "Extend Backend vtable (src/viewy/backend/api.nim) with caps + scheme/menu/tray/window-event slots and new types" \
  -d "Today Backend is a 16-slot closure-vtable object (create/destroy/run/terminate/dispatch/dispatchEval/dispatchResolve/setTitle/setSize/navigate/setHtml/eval/init/bindFn/unbind/resolve). Additively extend it WITHOUT breaking existing slots: add caps:set[Capability], registerScheme, setAppMenu, trayCreate/trayUpdate/trayDestroy, onWindowEvent. Add new types AssetRequest/AssetResponse/AssetHandler, MenuItem, TrayOptions, WindowEvent, Capability. Keep handle-based (no globals) so v2.x multi-window needs no rewrite. Reservation: src/viewy/backend/api.nim." \
  -p 0 -l impl -t task --silent)

CAP_GATING=$(bd create "Add Capability set + strdefine-driven capability gating (compile-time error + runtime caps-set assert)" \
  -d "Backend caps are gated two ways. Compile path: read a STRDEFINE (const selectedBackend {.strdefine: viewyBackend.} = native), derive a compile-time const, emit {.error.} from cap templates (trayCreate/setAppMenu/registerScheme) when the SELECTED backend lacks the cap. Runtime path: caps:set[Capability] membership assert for dynamically-injected vtable backends (tests). NOTE: there is no viewyBackend define today (app hard-imports wv) - do not gate on a nonexistent define; this introduces it. Reservation: src/viewy/backend/api.nim (cap templates)." \
  -p 0 -l impl -t task --silent)
bd dep add $CAP_GATING $EXTEND_API

SELECT_NIM=$(bd create "Create src/viewy/backend/select.nim and replace app.nim hard-import of wv/backend with when-defined selection" \
  -d "src/viewy/app.nim:7 currently hard-imports viewy/backend/wv/backend and defaults newApp(backend=newBackend()). Add src/viewy/backend/select.nim that selects newBackend() via when defined(...) keyed off the viewyBackend strdefine (native|lite), default native in v2. Re-point app.nim at select.nim. Reservation: src/viewy/backend/select.nim, src/viewy/app.nim (import line only)." \
  -p 0 -l impl -t task --silent)
bd dep add $SELECT_NIM $EXTEND_API
bd dep add $SELECT_NIM $CAP_GATING

DISPATCH_TERMINATE=$(bd create "Resolve dispatchTerminate / cross-thread terminate contract for v2 backends (Phase 0 decision)" \
  -d "dispatchTerminate + the typed handoff helpers are bare exports of wv/backend.nim + wv/handoff.nim, NOT Backend vtable slots; tests call them by name (test_windowed, test_async_rpc, test_wv_handoff, test_wv_teardown, test_emit_stress, test_assets_single). Native backends owe an equivalent cross-thread terminate path. DECIDE + record: either promote dispatchTerminate into the v2 vtable (additive, allowed) OR define a per-backend module-level export contract the tests import behind when. Blocking for the conformance suite. Reservation: src/viewy/backend/api.nim, design note in docs/native-backends.md." \
  -p 0 -l analysis -t task --silent)
bd dep add $DISPATCH_TERMINATE $EXTEND_API

ORC_MODEL=$(bd create "Reconcile ORC cross-thread memory model with docs/threading.md + handoff.nim; define binding invariant" \
  -d "docs/threading.md + wv/handoff.nim establish a STRICT invariant: no Nim-managed closure/string/seq/ref crosses the thread boundary - only C-heap SharedBytes via top-level {.cdecl,gcsafe.} callbacks. The plan's GC_ref'd-Nim-objects phrasing is a looser, different model; mixing them reintroduces the bug test_wv_handoff guards. State which model applies where (UI-thread scheme/menu callbacks vs worker-thread emit/resolve), make 'no managed type crosses threads' the binding invariant. Replace 'runs under valgrind' with a measurable bar (see CI valgrind bead). Reservation: docs/threading.md." \
  -p 0 -l analysis -t task --silent)
bd dep add $ORC_MODEL $EXTEND_API

ASSET_HANDLER=$(bd create "Introduce AssetHandler abstraction in src/viewy/assets.nim; reimplement served mode as a single AssetHandler consumer" \
  -d "Add the AssetRequest/AssetResponse/AssetHandler runtime abstraction to src/viewy/assets.nim. Reimplement assets_served.nim's loopback serving as ONE AssetHandler consumer code path so lite (served) and native (scheme) share serving logic. User-overridable app.assetHandler hook. Reservation: src/viewy/assets.nim, src/viewy/assets_served.nim." \
  -p 0 -l impl -t task --silent)
bd dep add $ASSET_HANDLER $EXTEND_API

ASSET_MODE_RECONCILE=$(bd create "Reconcile the dual AssetMode enums and add scheme mode + authoritative mapping + legacy parse" \
  -d "Two enums must reconcile (do NOT invent a string): cli/src/viewy_cli/config.nim {amSingle=single, amServed=served, default amSingle} - add amScheme=scheme and make it default; src/viewy/assets.nim {assetsEmbedded, assetsServedMode, assetsDevServer} - add a scheme runtime mode. Define ONE authoritative mapping fn (config string -> library mode), exact JSON wire strings, and legacy behavior: existing viewy.json with single/served or absent assets MUST still build - decide+document whether legacy forces lite, maps onto scheme handler, or warn-and-map. This is a config-schema change, not recompile-only. Reservation: cli/src/viewy_cli/config.nim, src/viewy/assets.nim." \
  -p 0 -l migration -t task --silent)
bd dep add $ASSET_MODE_RECONCILE $ASSET_HANDLER

SCHEME_SECURITY=$(bd create "Scheme-handler path security: canonicalize via normalizeAssetPath semantics; retire loopback token auth for scheme" \
  -d "viewy:// and https://viewy.localhost/ are a fresh untrusted-input surface. Canonicalize BEFORE asset-table lookup: reject/normalize .., decode percent-encoding exactly once (reject double-decoded %252e), reject absolute paths + backslashes, define case-sensitivity explicitly. Reuse normalizeAssetPath semantics from src/viewy/assets_served.nim so lite and native agree. RETIRE the loopback auth (__viewy_session cookie, per-launch Bearer token, rewriteAbsoluteAssetUrls in assets_served.nim) for scheme mode - it only made sense for a loopback HTTP port; retain it only for lite/served. State the retirement explicitly. Pure-logic (Tier-1 testable). Reservation: src/viewy/assets_served.nim, src/viewy/assets.nim." \
  -p 0 -l impl -t task --silent)
bd dep add $SCHEME_SECURITY $ASSET_HANDLER

RENAME_LITE=$(bd create "Rename src/viewy/backend/wv/ -> backend/lite/ (frozen); nil new slots; add deprecated wv compat shim" \
  -d "Move src/viewy/backend/wv/{ffi,backend,build,handoff}.nim to src/viewy/backend/lite/ (frozen, bugfix-only). Nil-out unsupported new vtable slots (registerScheme/setAppMenu/tray*) so caps reports them absent. Reimplement served mode internally as an AssetHandler consumer (one code path). COMPAT SHIM: keep old import path src/viewy/backend/wv/backend re-exporting lite (app.nim and tests/templates currently import viewy/backend/wv/backend) with an explicit deprecation. Reservation: src/viewy/backend/lite/**, src/viewy/backend/wv/** (shim only)." \
  -p 0 -l prep -t task --silent)
bd dep add $RENAME_LITE $EXTEND_API
bd dep add $RENAME_LITE $ASSET_HANDLER

WINDOW_EVENTS=$(bd create "Add net-new window-lifecycle public API (App.on / WindowEvent / onWindowEvent) with cross-thread delivery + test" \
  -d "There is NO App.on, WindowEvent, or window-event plumbing today (src/viewy/events.nim is backend->JS emit only: emitScript/emit). app.on(WindowClose)/onWindowEvent need their own WindowEvent type, cross-thread delivery from native close handlers (subject to the ORC model), and their own conformance test. Distinct from the menu-DSL work - do NOT fold in. Reservation: src/viewy/events.nim, src/viewy/app.nim (App.on)." \
  -p 1 -l impl -t feature --silent)
bd dep add $WINDOW_EVENTS $EXTEND_API
bd dep add $WINDOW_EVENTS $ORC_MODEL

ACCEL_PARSER=$(bd create "Implement platform-agnostic accelerator parser (CmdOrCtrl+... -> per-platform) + Tier-1 unit tests" \
  -d "Shared accelerator-string parser consumed by all three menu backends. CmdOrCtrl+Key, Shift/Alt/Super modifiers, mapped per platform (macOS Cmd, Linux/Windows Ctrl). Pure logic - full Tier-1 coverage (parse, invalid-string rejection, per-platform mapping). Reservation: src/viewy/menu.nim (new) or src/viewy/app.nim accel section, tests/test_accel.nim (new)." \
  -p 1 -l impl -t task --silent)
bd dep add $ACCEL_PARSER $EXTEND_API

SCHEME_ROUTING_TESTS=$(bd create "Tier-1 unit tests: scheme path->asset-table routing, MIME inference, SPA index.html fallback, traversal rejection" \
  -d "Bulk of behavioral verification runs headlessly everywhere. Cover: path->asset-table routing, MIME inference, SPA index.html fallback, 404, query strings, and path canonicalization/traversal rejection (the SCHEME_SECURITY rules). Follow tests/test_assets*.nim + test_served_auth.nim patterns. Reservation: tests/test_scheme_routing.nim (new), tests/test_assets*.nim." \
  -p 1 -l testing -t task --silent)
bd dep add $SCHEME_ROUTING_TESTS $ASSET_MODE_RECONCILE
bd dep add $SCHEME_ROUTING_TESTS $SCHEME_SECURITY

CONFORMANCE_RESTRUCTURE=$(bd create "Restructure v1 suite into 3 tiers; generalize/rename test_wv_* to compile-select -d:viewyBackend=native|lite" \
  -d "The v1 suite is the lite<->native conformance contract but does NOT all parameterize. Tier-1 (pure logic, headless everywhere): test_rpc, test_events, test_assets*, test_served_auth, accel/scheme routing. Tier-2 (real-backend smoke, gated like VIEWY_SKIP_WINDOWED): test_windowed, test_wv_handoff, test_wv_teardown, test_emit_stress, test_async_rpc, test_assets_single - hardwired to a real newBackend()+display, NOT stub-runnable. 'Parameterize' here = compile-select -d:viewyBackend=native|lite and run the same body on a real display. These call wv-specific exports (dispatchTerminate) - generalize/rename test_wv_* is part of this bead. Tier-3 manual = docs/qa-checklist.md. Reservation: tests/** (coordinate)." \
  -p 0 -l testing -t task --silent)
bd dep add $CONFORMANCE_RESTRUCTURE $DISPATCH_TERMINATE
bd dep add $CONFORMANCE_RESTRUCTURE $CAP_GATING

ASSETS_GEN_TABLE=$(bd create "CLI: generate viewy_assets.nim as a path->gzip multi-file table for scheme mode (assets_gen.nim + build.nim flags)" \
  -d "Today cli/src/viewy_cli/assets_gen.nim emits single-file (staticRead viewyEmbeddedHtml) or served (gzip table + sidecars). Add scheme generation: compile-time path->gzip asset table viewy_assets.nim with MIME + ETag-from-build-hash, multi-file. build.nim: emit the -d for scheme mode + native link flags (parallel to existing -d:viewyGeneratedAssets / -d:viewyGeneratedServedAssets). Reservation: cli/src/viewy_cli/assets_gen.nim, cli/src/viewy_cli/build.nim." \
  -p 1 -l impl -t task --silent)
bd dep add $ASSETS_GEN_TABLE $ASSET_MODE_RECONCILE

DOC_QA_CHECKLIST=$(bd create "Create docs/qa-checklist.md as the NAMED owner of Tier-3 manual QA" \
  -d "CI cannot observe menu-bar rendering, accelerator firing, tray icon/theme-swap, or quit-from-tray lifecycle (macOS/Windows hosted CI cannot drive global menus/tray headlessly). docs/qa-checklist.md is the binding per-phase acceptance gate for those. Seed it now so each phase appends its manual items. Reservation: docs/qa-checklist.md." \
  -p 1 -l docs -t task --silent)
bd dep add $DOC_QA_CHECKLIST $EXTEND_API

LITE_GREEN_P0=$(bd create "Phase 0 gate: -d:viewyBackend=lite builds + passes v1 examples + Tier-1/Tier-2 lite tests (rollback contract)" \
  -d "Per-phase 'lite still green' gate = the rollback contract, made concrete. At the Phase 0 boundary, -d:viewyBackend=lite must build and pass the v1 example + Tier-1/Tier-2 lite tests unchanged (lite is byte-for-byte the old wv path, frozen). Reservation: none (verification gate)." \
  -p 0 -l testing -t task --silent)
bd dep add $LITE_GREEN_P0 $RENAME_LITE
bd dep add $LITE_GREEN_P0 $CAP_GATING
bd dep add $LITE_GREEN_P0 $ASSET_MODE_RECONCILE
bd dep add $LITE_GREEN_P0 $SELECT_NIM

# ============================================================================
# PHASE 1 — Linux native backend (end-to-end, derisks the interface)
#   Ordering within phase: ffi -> window -> {ipc, scheme, menus, tray}
# ============================================================================

LINUX_GTK_FFI=$(bd create "Linux: native/linux/gtk_ffi.nim - pure Nim C FFI GTK3 bindings" \
  -d "Hand-written pure-Nim C FFI for GTK3 (no glue files; glue language LOCKED to pure Nim FFI on Linux). Only the surface the backend needs: window create/show, signals, main loop, menu + tray plumbing entry points. Reservation: src/viewy/backend/native/linux/gtk_ffi.nim." \
  -p 1 -l impl -t task --silent)
bd dep add $LINUX_GTK_FFI $EXTEND_API

LINUX_WEBKIT_FFI=$(bd create "Linux: native/linux/webkitgtk_ffi.nim - webkit2gtk-4.1 (>= 2.40) FFI" \
  -d "Pure-Nim FFI for webkit2gtk-4.1. Baseline GTK3 + webkit2gtk-4.1 >= 2.40 (request bodies need >= 2.40). GTK4/webkitgtk-6.0 is a separate future backend, NOT a flag of this one. Surface: WKWebView equivalent, settings, user-content-manager (init script + script message handler), URI scheme registration. Reservation: src/viewy/backend/native/linux/webkitgtk_ffi.nim." \
  -p 1 -l impl -t task --silent)
bd dep add $LINUX_WEBKIT_FFI $EXTEND_API

LINUX_WINDOW=$(bd create "Linux: backend.nim window + webview lifecycle (create/destroy/run/terminate/title/size/navigate/setHtml)" \
  -d "Implement the core Backend vtable slots for Linux behind a handle-based struct (no globals). Top-level {.cdecl.} callbacks with pointer userdata -> GC_ref'd Nim objects per the ORC model. Provide the native cross-thread terminate path per the dispatchTerminate decision. Reservation: src/viewy/backend/native/linux/backend.nim." \
  -p 1 -l impl -t feature --silent)
bd dep add $LINUX_WINDOW $LINUX_GTK_FFI
bd dep add $LINUX_WINDOW $LINUX_WEBKIT_FFI
bd dep add $LINUX_WINDOW $DISPATCH_TERMINATE

LINUX_IPC=$(bd create "Linux: IPC bind + init-script parity (RPC envelope + __viewy runtime + window.<name> Promise)" \
  -d "Native backends generate the JS bridge differently than webview_bind, so the docs/protocol.md envelope and the injected __viewy runtime (runtime_js.nim viewyRuntimeJs) must be hand-reproduced. Implement bindFn -> window.<name> returning a Promise, init() script injection before page scripts, dispatchEval/dispatchResolve under the ORC worker-thread model (script message handler -> Nim). Assert RPC-envelope parity and runtime_js bind parity. Reservation: src/viewy/backend/native/linux/backend.nim." \
  -p 1 -l impl -t feature --silent)
bd dep add $LINUX_IPC $LINUX_WINDOW
bd dep add $LINUX_IPC $ORC_MODEL

LINUX_SCHEME=$(bd create "Linux: viewy:// scheme handler via WebKitURISchemeRequest (multi-file, MIME, SPA fallback, POST, range)" \
  -d "Serve embedded multi-file assets from the path->gzip table via registerScheme/WebKitURISchemeRequest. Relative fetch() works, MIME inference, SPA index.html fallback, 404s, query strings, POST/request bodies (require webkit2gtk >= 2.40 - documented minimum), range requests for embedded media. No network port. Reservation: src/viewy/backend/native/linux/backend.nim (scheme section)." \
  -p 1 -l impl -t feature --silent)
bd dep add $LINUX_SCHEME $LINUX_WINDOW
bd dep add $LINUX_SCHEME $ASSET_HANDLER
bd dep add $LINUX_SCHEME $SCHEME_SECURITY
bd dep add $LINUX_SCHEME $ASSETS_GEN_TABLE

LINUX_MENUS=$(bd create "Linux: GTK menu bar (per-window) + context menus, dispatch by id, accelerators" \
  -d "setAppMenu via GTK menu bar (per-window on Linux) plus context menus. Dispatch MenuItem by id; accelerators via the shared ACCEL_PARSER. Reservation: src/viewy/backend/native/linux/backend.nim (menu section)." \
  -p 2 -l impl -t feature --silent)
bd dep add $LINUX_MENUS $LINUX_WINDOW
bd dep add $LINUX_MENUS $ACCEL_PARSER

LINUX_TRAY=$(bd create "Linux: native/linux/appindicator.nim tray via libayatana-appindicator3 (dlopen soft dep, graceful degradation)" \
  -d "System tray: icon, tooltip, attached menu, click events, light/dark variants. libayatana-appindicator3 is a RUNTIME soft dependency (dlopen; degrade gracefully if absent - runtime capability report). GNOME SNI: documented extension requirement. Reservation: src/viewy/backend/native/linux/appindicator.nim, backend.nim (tray section)." \
  -p 2 -l impl -t feature --silent)
bd dep add $LINUX_TRAY $LINUX_WINDOW

GTK4_RECONCILE=$(bd create "Reconcile GTK4 conflict: native Linux is GTK3-only; reword doctor.nim gtk4/-d:viewyGtk4 probe" \
  -d "cli/src/viewy_cli/doctor.nim probes gtk4 + webkitgtk-6.0 FIRST for -d:viewyGtk4, but native Linux targets GTK3 + webkit2gtk-4.1 only. Decide whether -d:viewyGtk4 is retired, kept for lite, or errors under native, and reword doctor accordingly. Reservation: cli/src/viewy_cli/doctor.nim." \
  -p 1 -l prep -t task --silent)
bd dep add $GTK4_RECONCILE $LINUX_WINDOW

LINUX_CONFORMANCE=$(bd create "Linux: run Tier-2 windowed suite + scheme conformance against -d:viewyBackend=native under xvfb" \
  -d "Full v1 RPC suite green against the Linux native backend (window+webview+IPC+init-script parity with lite). Run the restructured Tier-2 windowed/handoff/teardown/emit tests compile-selected to native on a real display (xvfb). Add scheme conformance tests (relative fetch, MIME, SPA fallback, 404, query, POST, range). Tray: assert no-crash + graceful degradation when appindicator absent. Reservation: tests/**." \
  -p 1 -l testing -t task --silent)
bd dep add $LINUX_CONFORMANCE $LINUX_IPC
bd dep add $LINUX_CONFORMANCE $LINUX_SCHEME
bd dep add $LINUX_CONFORMANCE $CONFORMANCE_RESTRUCTURE
bd dep add $LINUX_CONFORMANCE $SCHEME_ROUTING_TESTS

LITE_GREEN_P1=$(bd create "Phase 1 gate: -d:viewyBackend=lite still builds + passes v1 examples + Tier-1/Tier-2 lite tests" \
  -d "Rollback contract at the Phase 1 boundary. Reservation: none (verification gate)." \
  -p 1 -l testing -t task --silent)
bd dep add $LITE_GREEN_P1 $LINUX_CONFORMANCE
bd dep add $LITE_GREEN_P1 $LITE_GREEN_P0

# ============================================================================
# PHASE 2 — macOS native backend (interface FROZEN after this phase)
#   Sequencing: Linux end-to-end before touching macOS.
# ============================================================================

DARWIN_GLUE=$(bd create "macOS: native/darwin/glue.m + glue.h thin Obj-C glue (C ABI) compiled via {.compile.}" \
  -d "Glue language LOCKED: macOS = thin Obj-C .m glue via {.compile.} exposing C-ABI exports, Nim side pure C FFI. Zero Xcode project. Glue covers what cannot be reached from pure FFI (NSApplication/NSWindow/WKWebView/NSMenu/NSStatusItem bridging). Reservation: src/viewy/backend/native/darwin/glue.m, glue.h." \
  -p 1 -l impl -t task --silent)
bd dep add $DARWIN_GLUE $LINUX_CONFORMANCE

DARWIN_WINDOW=$(bd create "macOS: backend.nim Cocoa window + webview lifecycle (Nim side pure C FFI over glue)" \
  -d "Core Backend vtable slots for macOS via the C-ABI glue. Handle-based, no globals. Native cross-thread terminate per the dispatchTerminate decision. Reservation: src/viewy/backend/native/darwin/backend.nim." \
  -p 1 -l impl -t feature --silent)
bd dep add $DARWIN_WINDOW $DARWIN_GLUE

DARWIN_IPC=$(bd create "macOS: IPC bind + init-script parity via WKScriptMessageHandler (RPC envelope + __viewy runtime)" \
  -d "Reproduce the docs/protocol.md envelope + runtime_js __viewy runtime + window.<name> Promise on WKWebView (WKUserScript init injection, WKScriptMessageHandler -> Nim). dispatchEval/dispatchResolve under the ORC model. Assert RPC + runtime_js parity. Reservation: src/viewy/backend/native/darwin/backend.nim, glue.m." \
  -p 1 -l impl -t feature --silent)
bd dep add $DARWIN_IPC $DARWIN_WINDOW
bd dep add $DARWIN_IPC $ORC_MODEL

DARWIN_SCHEME=$(bd create "macOS: viewy:// scheme handler via WKURLSchemeHandler" \
  -d "Serve embedded multi-file assets via WKURLSchemeHandler from the path->gzip table. Relative fetch, MIME, SPA fallback, 404, query, range. No port. Reservation: src/viewy/backend/native/darwin/backend.nim (scheme), glue.m." \
  -p 1 -l impl -t feature --silent)
bd dep add $DARWIN_SCHEME $DARWIN_WINDOW
bd dep add $DARWIN_SCHEME $SCHEME_SECURITY
bd dep add $DARWIN_SCHEME $ASSETS_GEN_TABLE

DARWIN_MENUS=$(bd create "macOS: global NSMenu menu bar + working accelerators" \
  -d "setAppMenu renders in the GLOBAL macOS menu bar with working accelerators (Cmd mapping via ACCEL_PARSER). Dispatch by id. Reservation: src/viewy/backend/native/darwin/backend.nim (menu), glue.m." \
  -p 2 -l impl -t feature --silent)
bd dep add $DARWIN_MENUS $DARWIN_WINDOW
bd dep add $DARWIN_MENUS $ACCEL_PARSER

DARWIN_TRAY=$(bd create "macOS: NSStatusItem tray with template (light/dark) icon" \
  -d "System tray via NSStatusItem: icon, tooltip, attached menu, click events, template icon that adapts to light/dark menu bar. Reservation: src/viewy/backend/native/darwin/backend.nim (tray), glue.m." \
  -p 2 -l impl -t feature --silent)
bd dep add $DARWIN_TRAY $DARWIN_WINDOW

DARWIN_BUILD=$(bd create "macOS: build.nim bundle - Info.plist (NSHighResolutionCapable) + ad-hoc codesign" \
  -d "Extend the existing emitMacBundle path in cli/src/viewy_cli/build.nim: Info.plist with NSHighResolutionCapable (+ existing CFBundle keys) and ad-hoc codesign so the bundle passes codesign --force --deep -s -. Reservation: cli/src/viewy_cli/build.nim." \
  -p 2 -l impl -t task --silent)
bd dep add $DARWIN_BUILD $DARWIN_WINDOW

DARWIN_CONFORMANCE=$(bd create "macOS: run Tier-2 windowed suite against -d:viewyBackend=native on windowserver" \
  -d "Same parity suite green on macOS native. NOTE: macOS windowed tests do NOT run windowed today - this is new CI (see CI_MACOS_WINDOWED). .m glue compiles via {.compile.} with zero Xcode project. Reservation: tests/**." \
  -p 1 -l testing -t task --silent)
bd dep add $DARWIN_CONFORMANCE $DARWIN_IPC
bd dep add $DARWIN_CONFORMANCE $DARWIN_SCHEME
bd dep add $DARWIN_CONFORMANCE $CONFORMANCE_RESTRUCTURE

INTERFACE_FREEZE=$(bd create "Interface-freeze milestone: tag api.nim + native-backends.md interface section; gate all Windows work" \
  -d "Operationally define the freeze: a tagged commit of src/viewy/backend/api.nim + the interface section of docs/native-backends.md, taken AFTER macOS lands. All Windows beads depend on this. ESCAPE VALVE: if Windows finds a slot pure-Nim COM genuinely cannot implement, it files an interface-change RFC bead that re-opens the gate - it does NOT edit api.nim freely. Record the adjudication. Reservation: src/viewy/backend/api.nim (freeze tag), docs/native-backends.md." \
  -p 1 -l prep -t task --silent)
bd dep add $INTERFACE_FREEZE $DARWIN_CONFORMANCE
bd dep add $INTERFACE_FREEZE $DARWIN_MENUS
bd dep add $INTERFACE_FREEZE $DARWIN_TRAY
bd dep add $INTERFACE_FREEZE $DARWIN_BUILD

LITE_GREEN_P2=$(bd create "Phase 2 gate: -d:viewyBackend=lite still builds + passes v1 examples + Tier-1/Tier-2 lite tests" \
  -d "Rollback contract at the Phase 2 boundary. Reservation: none (verification gate)." \
  -p 1 -l testing -t task --silent)
bd dep add $LITE_GREEN_P2 $DARWIN_CONFORMANCE
bd dep add $LITE_GREEN_P2 $LITE_GREEN_P1

# ============================================================================
# PHASE 3 — Windows native backend (implements against the FROZEN interface)
# ============================================================================

WIN_COM_SPIKE=$(bd create "Windows: timeboxed spike - pure-Nim COM WebView2 environment creation, else C++-TU fallback" \
  -d "Spike with a STATED timebox (3 days) and binary acceptance: pure-Nim COM CreateCoreWebView2Environment succeeds on a clean Win11 VM with ONLY the Evergreen runtime, ELSE fall back to ONE retained C++ TU using v1's WEBVIEW_MSWEBVIEW2_BUILTIN_IMPL (build.nim already defines it). The C++-TU fallback partially reintroduces the shim v2 removes - note its CI/build-flag implications. Reservation: src/viewy/backend/native/windows/**, design note." \
  -p 1 -l analysis -t task --silent)
bd dep add $WIN_COM_SPIKE $INTERFACE_FREEZE

WIN_WINIM_MEASURE=$(bd create "Windows: measure winim size cost vs a concrete budget; default stays hand-written Win32+COM" \
  -d "winim is allowed ONLY if its size cost is acceptable after measurement against a concrete size-budget threshold (mirror the 3 MiB binary-size discipline). Default remains hand-written Win32 + minimal COM. Record the measurement + decision. Reservation: design note." \
  -p 2 -l analysis -t task --silent)
bd dep add $WIN_WINIM_MEASURE $INTERFACE_FREEZE

WIN_WEBVIEW2_PIN=$(bd create "Windows: pin WebView2 COM ABI to vendor/webview2/PIN (1.0.4022.49) for both lite builtin impl + native COM" \
  -d "The hand-written COM interfaces target a specific WebView2 SDK revision. Keep vendor/webview2/PIN (Microsoft.Web.WebView2 1.0.4022.49) authoritative for BOTH lite (C++ builtin impl) and the native COM declarations so they cannot drift. Reservation: vendor/webview2/PIN, docs/release-checklist.md (pin section)." \
  -p 1 -l prep -t task --silent)
bd dep add $WIN_WEBVIEW2_PIN $INTERFACE_FREEZE

WIN_COM=$(bd create "Windows: native/windows/com.nim - minimal hand-written COM interface set" \
  -d "COM declarations limited to required interfaces: ICoreWebView2, Environment, Controller, Settings, WebResourceRequested* plus handler/callback interfaces. No more. Reservation: src/viewy/backend/native/windows/com.nim." \
  -p 1 -l impl -t task --silent)
bd dep add $WIN_COM $WIN_COM_SPIKE
bd dep add $WIN_COM $WIN_WEBVIEW2_PIN

WIN_WIN32=$(bd create "Windows: native/windows/win32.nim - HWND, message loop, PerMonitorV2 DPI awareness" \
  -d "Pure-Nim Win32 bindings: window class/HWND, message loop, ACCEL table support, PerMonitorV2 DPI awareness. Reservation: src/viewy/backend/native/windows/win32.nim." \
  -p 1 -l impl -t task --silent)
bd dep add $WIN_WIN32 $INTERFACE_FREEZE

WIN_WEBVIEW2=$(bd create "Windows: native/windows/webview2.nim - environment/controller/settings wiring" \
  -d "Wire CreateCoreWebView2Environment -> Controller -> CoreWebView2 + Settings via the com.nim interfaces (or the C++-TU fallback if the spike chose it). Reservation: src/viewy/backend/native/windows/webview2.nim." \
  -p 1 -l impl -t feature --silent)
bd dep add $WIN_WEBVIEW2 $WIN_COM
bd dep add $WIN_WEBVIEW2 $WIN_WIN32

WIN_WINDOW=$(bd create "Windows: backend.nim window + webview lifecycle" \
  -d "Core Backend vtable slots for Windows over win32 + webview2. Handle-based, no globals. Native cross-thread terminate per the dispatchTerminate decision. Reservation: src/viewy/backend/native/windows/backend.nim." \
  -p 1 -l impl -t feature --silent)
bd dep add $WIN_WINDOW $WIN_WEBVIEW2

WIN_IPC=$(bd create "Windows: IPC bind + init-script parity (AddScriptToExecuteOnDocumentCreated + WebMessageReceived)" \
  -d "Reproduce the docs/protocol.md envelope + runtime_js __viewy runtime + window.<name> Promise via AddScriptToExecuteOnDocumentCreated (init) and WebMessageReceived (bind). dispatchEval/dispatchResolve under the ORC model. Assert RPC + runtime_js parity. Reservation: src/viewy/backend/native/windows/backend.nim." \
  -p 1 -l impl -t feature --silent)
bd dep add $WIN_IPC $WIN_WINDOW
bd dep add $WIN_IPC $ORC_MODEL

WIN_SCHEME=$(bd create "Windows: virtual host https://viewy.localhost/ via WebResourceRequested + in-memory IStream (SPA + range)" \
  -d "Serve embedded multi-file assets via SetVirtualHostNameToFolderMapping-equivalent / WebResourceRequested with in-memory IStream from the path->gzip table. Service-worker-less SPA + range requests for embedded media verified. No port. Reservation: src/viewy/backend/native/windows/backend.nim (scheme)." \
  -p 1 -l impl -t feature --silent)
bd dep add $WIN_SCHEME $WIN_WINDOW
bd dep add $WIN_SCHEME $SCHEME_SECURITY
bd dep add $WIN_SCHEME $ASSETS_GEN_TABLE

WIN_MENUS=$(bd create "Windows: HMENU menus + ACCEL table accelerators" \
  -d "Per-window HMENU menu bar + context menus, dispatch by id, accelerators via an ACCEL table (ACCEL_PARSER). Reservation: src/viewy/backend/native/windows/backend.nim (menu)." \
  -p 2 -l impl -t feature --silent)
bd dep add $WIN_MENUS $WIN_WINDOW
bd dep add $WIN_MENUS $ACCEL_PARSER

WIN_TRAY=$(bd create "Windows: Shell_NotifyIcon tray incl. dark/light icon swap" \
  -d "System tray via Shell_NotifyIcon: icon, tooltip, attached menu, click events, dark/light icon swap. Reservation: src/viewy/backend/native/windows/backend.nim (tray)." \
  -p 2 -l impl -t feature --silent)
bd dep add $WIN_TRAY $WIN_WINDOW

WIN_BUILD=$(bd create "Windows: build.nim emits PerMonitorV2 DPI manifest (+ ACCEL table wiring)" \
  -d "cli/src/viewy_cli/build.nim emits a PerMonitorV2 DPI-awareness manifest for the Windows build. Reservation: cli/src/viewy_cli/build.nim." \
  -p 2 -l impl -t task --silent)
bd dep add $WIN_BUILD $WIN_WINDOW

WIN_CONFORMANCE=$(bd create "Windows: run Tier-2 windowed suite against -d:viewyBackend=native on a non-interactive session" \
  -d "Same parity suite green on Windows native. Environment creation works on a clean Win11 VM with only the Evergreen runtime. Verify virtual-host SPA + range. Reservation: tests/**." \
  -p 1 -l testing -t task --silent)
bd dep add $WIN_CONFORMANCE $WIN_IPC
bd dep add $WIN_CONFORMANCE $WIN_SCHEME
bd dep add $WIN_CONFORMANCE $CONFORMANCE_RESTRUCTURE

LITE_GREEN_P3=$(bd create "Phase 3 gate: -d:viewyBackend=lite still builds + passes v1 examples + Tier-1/Tier-2 lite tests" \
  -d "Rollback contract at the Phase 3 boundary. Reservation: none (verification gate)." \
  -p 1 -l testing -t task --silent)
bd dep add $LITE_GREEN_P3 $WIN_CONFORMANCE
bd dep add $LITE_GREEN_P3 $LITE_GREEN_P2

# ============================================================================
# PHASE 4 — Unification, dev-mode HMR, CI, docs, examples, release
# ============================================================================

NATIVE_DEFAULT=$(bd create "Make native the default backend on all three platforms; finalize capability gating" \
  -d "Flip select.nim default to native across Linux/macOS/Windows; lite reachable via -d:viewyBackend=lite. Finalize compile-time cap gating so tray/menu/scheme calls fail at compile time on lite. Reservation: src/viewy/backend/select.nim." \
  -p 1 -l impl -t task --silent)
bd dep add $NATIVE_DEFAULT $LINUX_CONFORMANCE
bd dep add $NATIVE_DEFAULT $DARWIN_CONFORMANCE
bd dep add $NATIVE_DEFAULT $WIN_CONFORMANCE

HMR_SPIKE=$(bd create "Dev-mode HMR design spike under native (viewy:// origin breaks Vite ws derivation)" \
  -d "NOT a one-liner. Today dev mode bypasses assets and navigates straight to the Vite URL (app.nim viewyDev branch + cli dev.nim). If the page loads from a viewy:// origin, Vite's HMR client derives ws:// from location/import.meta and computes the WRONG WS target. Decide PER PLATFORM: pin server.hmr.{host,port,protocol} in vite.config.ts, OR keep the plain navigate(devUrl) path (Windows virtual-host may differ from viewy://). Output: a decision doc. Reservation: design note in docs/native-backends.md." \
  -p 1 -l analysis -t task --silent)
bd dep add $HMR_SPIKE $NATIVE_DEFAULT

HMR_IMPL=$(bd create "Implement dev-mode HMR per spike + extend cli/tests/test_devloop.nim with file-touch->update-marker test" \
  -d "Implement the HMR_SPIKE decision in template vite.config.ts (hmr pin) and/or cli/src/viewy_cli/dev.nim per platform. Acceptance: a concrete automated file-touch->update-marker test where feasible (extend cli/tests/test_devloop.nim, which today only checks the app<->devserver handshake), otherwise an explicit docs/qa-checklist.md manual item. Reservation: cli/src/viewy_cli/dev.nim, templates/**/vite.config.ts, cli/tests/test_devloop.nim." \
  -p 2 -l impl -t feature --silent)
bd dep add $HMR_IMPL $HMR_SPIKE

DOCTOR_CHECKS=$(bd create "viewy doctor: per-platform native checks (WebView2 runtime, webkit2gtk >= 2.40, appindicator presence)" \
  -d "Extend cli/src/viewy_cli/doctor.nim: Windows WebView2 Evergreen runtime, Linux webkit2gtk >= 2.40 (version check, not just presence) + appindicator presence, macOS toolchain. Compose with GTK4_RECONCILE wording. Reservation: cli/src/viewy_cli/doctor.nim." \
  -p 2 -l impl -t task --silent)
bd dep add $DOCTOR_CHECKS $NATIVE_DEFAULT
bd dep add $DOCTOR_CHECKS $GTK4_RECONCILE

TEMPLATES_MULTIFILE=$(bd create "Templates: drop vite-plugin-singlefile from vanilla/svelte/react; emit normal multi-file dist" \
  -d "All three cli/src/viewy_cli/templates/{vanilla,svelte,react}/vite.config.ts import+use viteSingleFile() (pinned 2.3.3 in package.json). Remove the plugin + dependency; emit normal multi-file dist/ consumed by scheme mode. Keep server.port 5173 strictPort. Reservation: cli/src/viewy_cli/templates/**." \
  -p 2 -l migration -t task --silent)
bd dep add $TEMPLATES_MULTIFILE $ASSET_MODE_RECONCILE

# --- CI (decomposed; the prompt flags these as SEPARATE beads, not one ci.yml edit) ---

CI_VALGRIND=$(bd create "CI: add Linux valgrind job (--mm:orc -d:useMalloc) with WebKitGTK suppressions + xvfb" \
  -d "NOT installed/invoked in ci.yml today. apt install valgrind, add a WebKitGTK suppressions file, run under xvfb. Measurable bar (replaces 'runs under valgrind'): test_emit_stress + a scheme-flood test pass under --mm:orc -d:useMalloc + valgrind with ZERO 'definitely lost' and ZERO invalid reads. Slow + leak-noisy. Reservation: .github/workflows/ci.yml, ci/valgrind.supp." \
  -p 1 -l testing -t task --silent)
bd dep add $CI_VALGRIND $ORC_MODEL
bd dep add $CI_VALGRIND $LINUX_CONFORMANCE

CI_WEBKIT_VERSION=$(bd create "CI: assert ubuntu runner libwebkit2gtk-4.1-dev >= 2.40 (POST/range silently untestable below it)" \
  -d "ci.yml apt-installs libwebkit2gtk-4.1-dev unversioned. Add an explicit >= 2.40 assertion (pkg-config --atleast-version=2.40 webkit2gtk-4.1) or the POST/range scheme criteria can't actually be tested. Reservation: .github/workflows/ci.yml." \
  -p 1 -l testing -t task --silent)
bd dep add $CI_WEBKIT_VERSION $LINUX_SCHEME

CI_MACOS_WINDOWED=$(bd create "CI: enable windowed Tier-2 on macOS (does NOT run windowed today)" \
  -d "macOS windowed tests don't run windowed in CI today - Tier-2 on macOS is NEW CI. Enable the windowed suite against native on macos-latest windowserver. Reservation: .github/workflows/ci.yml." \
  -p 2 -l testing -t task --silent)
bd dep add $CI_MACOS_WINDOWED $DARWIN_CONFORMANCE

CI_MATRIX_DOUBLE=$(bd create "CI: windowed matrix x {lite,native} x 3 OS; replicate the 120s watchdog for native" \
  -d "The windowed matrix roughly doubles (each windowed test x {lite,native} x 3 OS). Replicate the existing 120s Python watchdog for the native runs. Keep VIEWY_SKIP_WINDOWED gating where no display. Reservation: .github/workflows/ci.yml." \
  -p 2 -l testing -t task --silent)
bd dep add $CI_MATRIX_DOUBLE $CONFORMANCE_RESTRUCTURE
bd dep add $CI_MATRIX_DOUBLE $NATIVE_DEFAULT

CI_BUILD_ASSERTS=$(bd create "CI: build-output assertions - macOS codesign+Info.plist, Windows PerMonitorV2 manifest (mirror binary-size assert)" \
  -d "Add cli/tests assertions mirroring the existing 3 MiB binary-size check: macOS bundle has Info.plist (NSHighResolutionCapable) and passes ad-hoc codesign; Windows build emits a PerMonitorV2 manifest. Reservation: cli/tests/test_build.nim, .github/workflows/ci.yml." \
  -p 2 -l testing -t task --silent)
bd dep add $CI_BUILD_ASSERTS $DARWIN_BUILD
bd dep add $CI_BUILD_ASSERTS $WIN_BUILD

CI_SNI_GAP_DOC=$(bd create "Document the Linux CI tray gap: hosted runners have no SNI host, so the positive tray path is never CI-tested" \
  -d "Linux hosted CI has no StatusNotifierItem host, so the POSITIVE tray path is never CI-tested on Linux (only no-crash + graceful degradation). Document this gap explicitly in docs/qa-checklist.md / ci-notes.md. Reservation: docs/qa-checklist.md, docs/ci-notes.md." \
  -p 3 -l docs -t task --silent)
bd dep add $CI_SNI_GAP_DOC $LINUX_TRAY

# --- Docs & examples ---

DOC_NATIVE_BACKENDS=$(bd create "Docs: write docs/native-backends.md (architecture + interface section that the freeze tags)" \
  -d "New docs/native-backends.md: per-platform native architecture (Linux FFI / macOS glue / Windows COM), the uniform Nim API, the asset-scheme model, and the interface section that INTERFACE_FREEZE tags. Reservation: docs/native-backends.md." \
  -p 2 -l docs -t task --silent)
bd dep add $DOC_NATIVE_BACKENDS $INTERFACE_FREEZE

DOC_LIMITATIONS_MATRIX=$(bd create "Docs: update docs/limitations.md with the lite-vs-native capability matrix" \
  -d "Update docs/limitations.md with the lite vs native capability matrix (scheme/menus/tray/window-events per backend) and platform baselines (GTK3+webkit2gtk-4.1>=2.40, Evergreen WebView2). Reservation: docs/limitations.md." \
  -p 2 -l docs -t task --silent)
bd dep add $DOC_LIMITATIONS_MATRIX $NATIVE_DEFAULT

DOC_MIGRATION_GUIDE=$(bd create "Docs: v1->v2 migration guide (scoped backwards-compat, NOT zero-change)" \
  -d "Migration guide: v2 flips two defaults (backend wv->native, asset mode embedded->scheme). Guarantee (a): recompile with -d:viewyBackend=lite is byte-for-byte v1. Guarantee (b): recompile on native builds without source edits but asset-loading semantics CHANGE (documented behavior change, not zero-change). viewy.json single/served still parse per ASSET_MODE_RECONCILE mapping. wv import path deprecated via shim. Reservation: docs/migration-v2.md (new), docs/limitations.md." \
  -p 2 -l docs -t task --silent)
bd dep add $DOC_MIGRATION_GUIDE $ASSET_MODE_RECONCILE
bd dep add $DOC_MIGRATION_GUIDE $RENAME_LITE

EXAMPLE_TRAY=$(bd create "Example: examples/tray-app (background, tray-only, hidden window)" \
  -d "New examples/tray-app demonstrating tray icon/tooltip/menu, click events, light/dark variants, and a background/tray-only app with a hidden window (window-attachment is a stretch goal). Exercises tray on all three native backends. Reservation: examples/tray-app/**." \
  -p 2 -l docs -t feature --silent)
bd dep add $EXAMPLE_TRAY $LINUX_TRAY
bd dep add $EXAMPLE_TRAY $DARWIN_TRAY
bd dep add $EXAMPLE_TRAY $WIN_TRAY

EXAMPLE_MENUS=$(bd create "Example: examples/menus (app menu bar + context menus + accelerators)" \
  -d "New examples/menus demonstrating the menu DSL (menuBar/submenu/onMenu), accelerators, and context menus across all three native backends. Reservation: examples/menus/**." \
  -p 2 -l docs -t feature --silent)
bd dep add $EXAMPLE_MENUS $LINUX_MENUS
bd dep add $EXAMPLE_MENUS $DARWIN_MENUS
bd dep add $EXAMPLE_MENUS $WIN_MENUS

# --- Housekeeping / release ---

VERSION_BUMP=$(bd create "Bump viewy.nimble + cli/viewy_cli.nimble 0.1.0 -> 0.2.0 (breaking)" \
  -d "Both packages are 0.1.0. A backend rewrite + 3 features + two default flips is at least a 0.2.0 breaking bump. Bump both viewy.nimble and cli/viewy_cli.nimble. Reservation: viewy.nimble, cli/viewy_cli.nimble." \
  -p 2 -l cleanup -t chore --silent)
bd dep add $VERSION_BUMP $NATIVE_DEFAULT

CHANGELOG_02=$(bd create "Add CHANGELOG.md 0.2.0 section (native default, scheme assets, menus, tray, lite demotion)" \
  -d "CHANGELOG.md top is '0.1.0 - Draft'. Add a 0.2.0 section: native backend default, viewy:// scheme assets, native menus, system tray, window-events, wv demoted to lite, default flips, viewy.json scheme default. Reservation: CHANGELOG.md." \
  -p 2 -l docs -t chore --silent)
bd dep add $CHANGELOG_02 $NATIVE_DEFAULT

RELEASE_CHECKLIST_UPD=$(bd create "Update docs/release-checklist.md (still pins webview/webview + WebView2; add native baselines)" \
  -d "docs/release-checklist.md still pins webview/webview 0.12.0 + WebView2 1.0.4022.49 only. Update for v2: keep WebView2 1.0.4022.49 pin authoritative for native COM (WIN_WEBVIEW2_PIN), add GTK3+webkit2gtk-4.1>=2.40 baseline, libayatana-appindicator3 soft dep, and the 0.2.0 tag. Reservation: docs/release-checklist.md." \
  -p 2 -l docs -t chore --silent)
bd dep add $RELEASE_CHECKLIST_UPD $VERSION_BUMP
bd dep add $RELEASE_CHECKLIST_UPD $WIN_WEBVIEW2_PIN

echo "Done. Run 'bd ready' to see initial unblocked work and 'bd dep cycles' to confirm no cycles."
