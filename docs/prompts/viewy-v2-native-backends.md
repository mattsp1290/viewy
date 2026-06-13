# Big Change Planning with Beads

## Agent Instructions

You are an expert software architect creating a comprehensive task breakdown for a change to an existing codebase. This task graph will be executed by AI agents working in parallel, coordinated through MCP Agent Mail with file reservations to prevent conflicts.

<quality_expectations>
Create a thorough, production-ready task graph. Include all necessary analysis, preparation, implementation, testing, and documentation tasks. Go beyond the basics — consider edge cases, error handling, security considerations, backwards compatibility, and integration points. Each task should be specific enough for an agent to execute independently without ambiguity.
</quality_expectations>

<critical_constraint>
You must NOT implement any of the changes yourself. Your ONLY output is a bash shell script containing `bd create` and `bd dep add` commands. Do NOT use `bd add` — the correct command is `bd create`. Do not write code. Do not create files other than the shell script. Do not modify existing files. Read and analyze the codebase, then produce the script.
</critical_constraint>

## Change Information

### Change Type
**MIGRATION** (with a substantial NEW_FEATURE component).

Primary driver: replace the `webview/webview` C/C++ shim with Wails-style direct
native backends per platform. Secondary: this migration unlocks three new
features (custom URI schemes, native menus, system tray) that the shim cannot
structurally provide.

### Description
Replace the webview/webview shim with Wails-style direct native backends on
Linux (GTK3 + WebKitGTK via pure Nim C FFI), macOS (Cocoa via thin Objective-C
glue compiled with `{.compile.}`, Nim side pure C FFI), and Windows (Win32 +
WebView2 via pure Nim COM). This unlocks three features the v1 `wv` backend
structurally cannot provide:

1. **Custom URI schemes** — serve embedded assets via `viewy://` (macOS/Linux)
   and a virtual host (`https://viewy.localhost/`) on Windows. Removes both v1
   asset-mode limitations: no single-file constraint, no loopback port, relative
   `fetch()` works, proper streaming/range support.
2. **Native menus** — app menu bar (global on macOS, per-window elsewhere) plus
   context menus.
3. **System tray** — icon, tooltip, attached menu, click events, light/dark icon
   variants (window-attachment is a stretch goal).

The Wails v3 model is the reference architecture: native code per platform behind
a uniform Nim API, in-memory asset handling, no network ports. The v1 `wv`
backend is kept but demoted to a `lite` backend (`-d:viewyBackend=lite`); native
is the default in v2. Capability gating makes tray/menu/scheme calls fail (ideally
at compile time) on lite. Multi-window and mobile remain out of scope, but the new
backend interface must be handle-based (no globals) so v2.x can add multi-window
without another rewrite.

Delivered in phases: Phase 0 (v2 interface + asset-pipeline groundwork, no native
code), Phase 1 (Linux end-to-end), Phase 2 (macOS), Phase 3 (Windows), Phase 4
(unification + release).

### Links to Relevant Documentation
- `docs/viewy-spec.md` (also at `/Users/punk1290/Downloads/viewy-spec.md`) — the viewy v1 spec; baseline this change assumes is complete.
- `docs/architecture.md`, `docs/protocol.md`, `docs/limitations.md`, `docs/threading.md`, `docs/served-mode.md` — existing v1 design docs to extend.
- [Wails dynamic assets / AssetsHandler](https://wails.io/docs/guides/dynamic-assets/) — the asset-handler/middleware model the plan mirrors.
- [Wails custom protocol schemes](https://wails.io/docs/guides/custom-protocol-schemes/) — reference for scheme handling.
- [Wails v3 architecture](https://v3.wails.io/concepts/architecture/) — reference architecture (native code per platform behind a uniform API, no ports).
- [Wails build system](https://v3alpha.wails.io/concepts/build-system/) — single-binary embedded-asset build reference.

### Affected Areas
- **Backend interface:** `src/viewy/backend/api.nim` — extend the v1 closure-vtable with `caps*: set[Capability]`, `registerScheme`, `setAppMenu`, `trayCreate/Update/Destroy`, `onWindowEvent`, and the new `AssetRequest`/`AssetResponse`/`AssetHandler`/`MenuItem`/`TrayOptions`/`WindowEvent` types.
- **Lite backend (renamed):** `src/viewy/backend/wv/{ffi.nim, backend.nim, build.nim, handoff.nim}` → `src/viewy/backend/lite/` (frozen, bugfix-only); nil-out unsupported new slots; reimplement `served` mode internally as an `AssetHandler` consumer.
- **New native backends:** `src/viewy/backend/native/linux/{backend.nim, gtk_ffi.nim, webkitgtk_ffi.nim, appindicator.nim}`, `native/darwin/{backend.nim, glue.m, glue.h}`, `native/windows/{backend.nim, win32.nim, com.nim, webview2.nim}`, and `src/viewy/backend/select.nim` (`when defined(...)` selection).
- **Asset pipeline:** `src/viewy/assets.nim`, `src/viewy/assets_served.nim` — new default `assets = "scheme"` mode; compile-time gzip asset table; MIME inference; SPA `index.html` fallback; ETag from build hash; user-overridable `app.assetHandler`; dev-mode proxy to Vite.
- **Public API + IPC:** `src/viewy/app.nim` (menu DSL `menuBar`/`submenu`, `onMenu`, `trayCreate`, `app.on(WindowClose)`, capability assertions), `src/viewy/events.nim`, `src/viewy/rpc.nim`, `src/viewy/runtime_js.nim` (IPC + init-script parity on native backends).
- **CLI:** `cli/src/viewy_cli/{assets_gen.nim, build.nim, dev.nim, doctor.nim, config.nim}` — generate `viewy_assets.nim` as a path→gzip table; native build/link flags; macOS Info.plist (`NSHighResolutionCapable`) + ad-hoc codesign; Windows PerMonitorV2 manifest + ACCEL table; doctor checks (WebView2 runtime, webkit2gtk ≥ 2.40, appindicator presence); dev-mode HMR proxy.
- **Templates:** `cli/src/viewy_cli/templates/{vanilla,svelte,react}/` — drop the `vite-plugin-singlefile` requirement; emit normal multi-file `dist/`.
- **Tests:** `tests/` (parameterize the v1 RPC/integration suite into a backend conformance suite; add scheme conformance tests) and `cli/tests/` (build/doctor changes). Existing relevant tests: `test_rpc.nim`, `test_assets*.nim`, `test_served_auth.nim`, `test_events.nim`, `test_emit_stress.nim`, `test_wv_handoff.nim`, `test_wv_teardown.nim`, `test_windowed.nim`, `test_dump_bindings.nim`.
- **Vendor:** `vendor/webview` (retained for lite), `vendor/webview2` (native WebView2 loader / built-in impl decision).
- **Docs & examples:** new `docs/native-backends.md`, `docs/qa-checklist.md`; updated `docs/limitations.md` (lite vs native capability matrix) and migration guide; `examples/tray-app` (background, tray-only, hidden window) and `examples/menus`.
- **CI:** `.github/workflows/ci.yml` — run the conformance suite across ubuntu (xvfb), macOS, and Windows.

### Success Criteria

**Testability note (the v1 suite does NOT all parameterize over a fake backend — split the conformance work into three honest tiers):**
- **Tier 1 — pure-logic unit tests (run headlessly everywhere):** RPC envelope (`tests/test_rpc.nim` uses no backend), accelerator-string→platform parsing, scheme path→asset-table routing, MIME inference, SPA `index.html` fallback, path canonicalization/traversal rejection. These are the bulk of behavioral verification.
- **Tier 2 — real-backend smoke (construct/teardown no-crash, gated like today's `VIEWY_SKIP_WINDOWED` windowed tests):** the windowed/handoff/teardown/emit tests (`tests/test_windowed.nim`, `test_wv_handoff.nim`, `test_wv_teardown.nim`, `test_emit_stress.nim`) are hardwired to a *real* `newBackend()` + a real display — they are NOT runnable against a stub. "Parameterize over backend" for these means compile-select `-d:viewyBackend=native|lite` and run the same test body on a real display (Linux xvfb; macOS windowserver; Windows non-interactive session). Note these tests are named `test_wv_*` and call `wv`-specific exports (e.g. `dispatchTerminate`, see §dispatchTerminate decision) — generalizing/renaming them is its own task.
- **Tier 3 — manual QA (`docs/qa-checklist.md` is the NAMED owner of what CI cannot observe):** menu-bar rendering, accelerator firing, tray icon/theme-swap, quit-from-tray lifecycle. macOS/Windows hosted CI cannot drive global menus or tray dispatch headlessly — the per-phase acceptance for those is the qa-checklist gate, not CI. Each phase's criteria below must state which tier verifies it.

1. Native backend is the **default** on all three platforms; the v1 RPC/integration suite, restructured into the three tiers above, runs across the CI matrix (ubuntu/xvfb, macOS, Windows). Tier-1 green everywhere; Tier-2 green where a display is available; Tier-3 tracked in `docs/qa-checklist.md`.
2. `viewy://` scheme (and Windows `https://viewy.localhost/` virtual host) serves embedded multi-file assets — relative `fetch()`, MIME inference, SPA `index.html` fallback, 404s, query strings, POST bodies, and range requests for embedded media all work. (Linux POST/request bodies require WebKitGTK ≥ 2.40, documented as the minimum.)
3. Native menus render and dispatch by `id` with working accelerators (`CmdOrCtrl+...` parsed per platform); system tray shows icon/tooltip/menu with light/dark variants and graceful degradation where unsupported (GNOME SNI: runtime capability report + documented extension requirement).
4. Dev-mode HMR verified working under the native backend on all three platforms. **This needs a design spike first** (it is not a one-liner): today dev mode bypasses assets entirely and `navigate`s straight to the Vite URL (`src/viewy/app.nim` dev branch, `cli/src/viewy_cli/dev.nim`). If the page is instead loaded from a `viewy://` origin, Vite's HMR client derives its `ws://` URL from `location`/`import.meta` and will compute the wrong WS target — so the templates must pin `server.hmr.{host,port,protocol}` in `vite.config.ts`, OR dev mode keeps the plain `navigate(devUrl)` path (decide per platform; Windows virtual-host may differ from `viewy://`). Acceptance: a concrete automated file-touch→update-marker test where feasible (extend `cli/tests/test_devloop.nim`, which today only checks the app↔devserver handshake), otherwise an explicit `docs/qa-checklist.md` manual item. As written this was not a checkable criterion.
5. The `lite` backend (former `wv`) still builds and passes the v1 examples/tests unchanged; v1 apps migrate with **zero code changes** (recompile only).
6. Docs shipped: `docs/native-backends.md`, updated `docs/limitations.md` capability matrix, migration guide, `docs/qa-checklist.md`; `examples/tray-app` and `examples/menus` added.
7. `viewy doctor` performs per-platform checks (WebView2 runtime, webkit2gtk version ≥ 2.40, appindicator presence). macOS `viewy build` emits a bundle that passes `codesign --force --deep -s -` ad-hoc signing; Windows build emits a PerMonitorV2 DPI manifest.

Per-phase acceptance criteria (binding):

**Phase 0 — Interface + assets groundwork (no native code):** Backend v2 interface, capability gating, menu/tray types, and asset-handler abstraction merged. Lite backend adapts (`registerScheme` nil; `served` reimplemented as an `AssetHandler` consumer — one code path). All v1 examples/tests pass unchanged on lite.

**Phase 1 — Linux native backend:** Window + webview + IPC + init-script parity with lite (full v1 RPC suite green against it). `viewy://` serves embedded multi-file assets; todo example runs without the singlefile plugin and relative `fetch()` works. Menus render and dispatch ids; tray works under a StatusNotifierItem host (CI: assert no-crash + graceful degradation when appindicator absent).

**Phase 2 — macOS native backend:** Same parity suite green; `.m` glue compiles via `{.compile.}` with zero Xcode project. `viewy://` via `WKURLSchemeHandler`; menus in the global menu bar with working accelerators; `NSStatusItem` tray with template icon. `viewy build` bundles Info.plist (`NSHighResolutionCapable` etc.) and passes ad-hoc codesign.

**Phase 3 — Windows native backend:** COM declarations limited to required interfaces; environment creation works on a clean Win11 VM with only the Evergreen runtime. Virtual host `https://viewy.localhost/` via `WebResourceRequested` + in-memory `IStream`; service-worker-less SPA + range requests for embedded media verified. `HMENU` menus + accelerators (ACCEL table); `Shell_NotifyIcon` tray incl. dark/light icon swap; clean DPI awareness (PerMonitorV2 manifest emitted by `viewy build`).

**Phase 4 — Unification & release:** Native is default; `viewy doctor` checks per platform. Dev-mode HMR verified on all three native backends. Docs (`native-backends.md`, updated `limitations.md` matrix, migration guide) and examples (`tray-app`, `menus`) shipped.

### Constraints
- **Backwards compatibility (scoped precisely — the bare "zero code changes" framing is NOT accurate):** v2 changes two defaults — the default backend flips `wv` → `native`, and the default asset mode flips single/embedded → `scheme`. A plain recompile therefore changes runtime behavior. The actual guarantee is: **(a)** a v1 app recompiled with `-d:viewyBackend=lite` behaves identically to v1 (lite is byte-for-byte the old `wv` path, frozen except bugfixes); **(b)** a v1 app recompiled on the native default builds and runs without *source* edits, but its asset-loading semantics change (single-file/hash-routing → scheme/multi-file) and that is a documented behavior change, not "zero change". Existing `viewy.json` files that set `assets: "single"` or `"served"` MUST continue to parse and work (mapped onto lite or onto the scheme handler per the mapping in §Asset-mode mapping below). The conformance suite is the lite↔native behavior contract. A **compatibility shim** must keep the old import path `src/viewy/backend/wv/backend` re-exporting `lite` so direct backend imports in user code don't break (`src/viewy/app.nim` currently hard-imports `viewy/backend/wv/backend`). Add an explicit deprecation path for the shim.
- **Per-platform glue languages are LOCKED:** Linux = pure Nim C FFI (no glue files). macOS = thin Obj-C `.m` glue via `{.compile.}` (C ABI exports), Nim side pure C FFI. Windows = pure Nim COM with a minimal hand-written interface set (ICoreWebView2, Environment, Controller, Settings, WebResourceRequested* + handler/callback interfaces); `winim` ONLY if its size cost is acceptable after measurement (default: hand-written Win32 + COM). Allowed fallback: keep one C++ TU for WebView2 environment creation (retain v1's `WEBVIEW_MSWEBVIEW2_BUILTIN_IMPL` approach) if pure-Nim creation proves painful — timeboxed before falling back.
- **Out of scope (do NOT build):** multi-window (but the backend interface MUST be handle-based / no globals so v2.x can add it without a rewrite), mobile, streaming asset responses (v2.0 returns full body), frameless/custom titlebars, TS bindgen. These are v2.x backlog. (TS bindgen design intent is recorded in `.agents/docs/roadmap/ts-bindgen.md`.)
- **Platform baselines:** Linux targets GTK3 + webkit2gtk-4.1 ≥ 2.40 (request bodies need ≥ 2.40); GTK4/webkitgtk-6.0 is a separate future backend, NOT a build flag of this one. Windows targets the Evergreen WebView2 runtime. `libayatana-appindicator3` is a runtime soft dependency (dlopen; degrade gracefully if absent).
- **Sequencing (binding):** Phase 0 in one PR. Then implement Linux end-to-end (window → scheme → menus → tray) before touching macOS — it derisks the interface design with the cheapest platform; interface tweaks after Linux are expected and allowed. After macOS lands, the interface is **frozen**; Windows implements against it with no changes allowed (file issues instead).
- **Memory safety:** all FFI callbacks are top-level `{.cdecl.}` procs with `pointer` userdata → `GC_ref`'d Nim objects; the conformance suite runs under `--mm:orc -d:useMalloc` + valgrind on Linux.
- **No network ports** for asset serving — in-memory handling only (Wails parity).
- **Scheme-handler security:** the new `viewy://` / `https://viewy.localhost/` handler is a fresh untrusted-input surface. Path lookups against the embedded asset table MUST be canonicalized before lookup — reject/normalize `..`, decode percent-encoding exactly once (reject double-decoded `%252e`), reject absolute paths and backslashes, and define case-sensitivity explicitly. Reuse `normalizeAssetPath` semantics from `src/viewy/assets_served.nim` so lite and native agree. The loopback **token/cookie auth** machinery (`__viewy_session`, per-launch bearer token, `rewriteAbsoluteAssetUrls` in `assets_served.nim`) only made sense for a loopback HTTP port — it is **removed for scheme mode** and retained only for lite/served. State this retirement explicitly.

### Asset-mode mapping (resolves the dual-enum collision)
There are two distinct `AssetMode`-style enums today and the new `scheme` mode touches both — a task MUST reconcile them, not invent a string:
- `cli/src/viewy_cli/config.nim`: `amSingle = "single"`, `amServed = "served"` — what `viewy.json` deserializes. Add `amScheme = "scheme"` here and make it the default.
- `src/viewy/assets.nim`: `assetsEmbedded`, `assetsServedMode`, `assetsDevServer` — the library runtime enum. Add the scheme runtime mode here.
Define one authoritative mapping function (config string → library mode), the exact JSON wire strings, and the legacy behavior: an existing `viewy.json` with `"single"`/`"served"` (or an absent `assets` field) must still build — decide and document whether legacy strings force lite, map onto the scheme handler, or warn-and-map. This is a config-schema change, not "recompile only".

---

## Your Task

Analyze this codebase change and create a comprehensive **Beads task graph** using the `bd` CLI. Beads provides dependency-aware, conflict-free task management for multi-agent execution.

Before creating the task graph, you MUST first analyze the affected areas of the codebase:

1. Check `docs/specs/` and `docs/adr/` for existing architectural decisions (note: this repo keeps design docs directly under `docs/` — read `docs/architecture.md`, `docs/protocol.md`, `docs/threading.md`, `docs/limitations.md`, `docs/served-mode.md`, and `docs/viewy-spec.md`).
2. Examine the directory/module structure of the affected areas listed above (`src/viewy/backend/`, `src/viewy/assets*.nim`, `src/viewy/app.nim`, `cli/src/viewy_cli/`, `tests/`, `cli/tests/`, `vendor/`).
3. Identify key interfaces, APIs, and integration points that must be preserved — especially the exact closure-vtable shape in `src/viewy/backend/api.nim` (do NOT break existing `Backend` slots) and the RPC JSON envelope in `docs/protocol.md`.
4. Note existing test patterns and coverage in the affected areas (`tests/test_rpc.nim`, `tests/test_assets*.nim`, `tests/test_served_auth.nim`, `tests/test_events.nim`, `tests/test_wv_handoff.nim`, `tests/test_wv_teardown.nim`, `cli/tests/test_build.nim`, `cli/tests/test_doctor.nim`) — the conformance suite must reuse these.
5. Assess risk areas where changes could break existing functionality (the lite backend rename, the asset-mode default change, capability gating, cross-thread GC handoff under ORC).

Use your analysis to make each bead specific — reference actual file paths, module names, and patterns you observed.

Then generate a shell script that creates the complete task graph.

**IMPORTANT: Your ONLY deliverable is a bash shell script with `bd create` commands. Not an implementation plan. Not a design document. Not a code review. A runnable `.sh` script.**

---

## Output Format

Generate a shell script that creates the full task graph. The script should:

1. **Initialize Beads** (if not already initialized)
2. **Create all beads** with appropriate priorities
3. **Establish dependencies** between beads
4. **Add labels** for phase grouping

### Example Output

```bash
#!/bin/bash
# Project: viewy
# Change: viewy v2 — native backends (tray, menus, custom schemes)
# Generated: 2026-06-13

set -e

# Initialize beads if needed
if [ ! -d ".beads" ]; then
    bd init
fi

echo "Creating change beads..."

# ========================================
# Phase 0: Interface + assets groundwork
# ========================================

EXTEND_API=$(bd create "Extend Backend vtable in src/viewy/backend/api.nim with caps + scheme/menu/tray/window-event slots and new types (AssetRequest/Response/Handler, MenuItem, TrayOptions, WindowEvent)" -p 0 --label impl --silent)

# NOTE: the backend is selected by a STRDEFINE -d:viewyBackend=lite|native, NOT a
# boolean `viewyBackendLite` define. The gating macro must read the strdefine
# (e.g. `const selectedBackend {.strdefine: "viewyBackend".} = "native"`), derive
# a compile-time `const`, and emit `{.error.}` from cap templates (trayCreate/
# setAppMenu/registerScheme) when the SELECTED backend lacks the cap. The runtime
# `caps*: set[Capability]` membership test is the fallback for dynamically-injected
# vtable backends (tests). State both paths; do not gate on a nonexistent define.
CAP_GATING=$(bd create "Add Capability set + strdefine-driven capability gating: compile-time {.error.} when selected backend lacks cap; runtime caps-set assert for injected backends" -p 0 --label impl --silent)
bd dep add $CAP_GATING $EXTEND_API

ASSET_ABSTRACTION=$(bd create "Introduce AssetHandler abstraction in src/viewy/assets.nim; reimplement served mode as a single AssetHandler consumer code path" -p 0 --label impl --silent)
bd dep add $ASSET_ABSTRACTION $EXTEND_API

RENAME_LITE=$(bd create "Rename src/viewy/backend/wv/ to backend/lite/ (frozen); nil unsupported new slots; keep v1 examples/tests green on lite" -p 0 --label prep --silent)
bd dep add $RENAME_LITE $EXTEND_API

# ... (continue: native Linux, macOS, Windows phases, conformance suite,
#      CLI changes, docs, examples, CI matrix, with dependencies)
```

---

## Bead Creation Guidelines

### Priority Levels
- `-p 0` = Critical (blocking other work, or high-risk changes needing early validation)
- `-p 1` = High (important implementation work)
- `-p 2` = Medium (standard work)
- `-p 3` = Low (cleanup, nice-to-haves)

### Labels (Phase Grouping)
Use `--label` to group beads by phase:
- `analysis` - Understanding current state
- `prep` - Preparation work (characterization tests, feature flags, scaffolding)
- `impl` - Core implementation
- `testing` - Test coverage
- `migration` - Data/code migration
- `docs` - Documentation updates
- `cleanup` - Post-rollout cleanup

### Dependency Rules
1. Never create cycles
2. Analysis tasks should complete before implementation begins
3. Characterization tests should exist before changing code
4. Use `bd dep add CHILD PARENT` (child depends on parent completing first)
5. Parallel work should share a common ancestor, not depend on each other

### Task Granularity
- Each bead should be completable in **under 750 lines of code changed**
- Tasks should be atomic enough for one agent to complete without coordination
- If a task requires multiple file areas, consider splitting by file area

---

## Change-Specific Considerations

### For New Features
- Start with analysis of similar existing features
- Consider feature flag for gradual rollout
- Plan for A/B testing if relevant
- Include documentation and changelog updates

### For Refactors
- Add characterization tests first (capture current behavior)
- Consider strangler fig pattern for large changes
- Plan incremental migration path
- Ensure no behavior changes unless intentional

### For Migrations
- Create rollback plan as an explicit task
- Plan data validation checkpoints
- Consider dual-write period if applicable
- Include monitoring/alerting tasks

### For Performance Changes
- Add benchmarks before and after
- Include load testing tasks
- Plan gradual rollout with monitoring
- Have rollback criteria defined

### Migration-specific notes for THIS change
- The v1 suite is the **conformance contract**, but it splits into the three tiers in §Success Criteria — do NOT scope it as a single "parameterize over backend" bead. Keep lite passing throughout (rollback safety net). Add a **per-phase "lite still green" gate bead**: at each phase boundary, `-d:viewyBackend=lite` must build and pass the v1 example + Tier-1/Tier-2 lite tests. That recurring gate IS the rollback contract — make it concrete, not implicit.
- **§dispatchTerminate decision (resolve in Phase 0):** `dispatchTerminate` and the typed cross-thread handoff helpers are NOT slots on the `Backend` vtable in `src/viewy/backend/api.nim` — they are bare exports of `wv/backend.nim`/`handoff.nim` that the stress/teardown tests call by name. Native backends owe an equivalent cross-thread terminate path. Decide and state: either **promote `dispatchTerminate` into the v2 vtable** (additive, allowed) or define a per-backend module-level export contract the tests import behind `when`. Pick one; it's blocking for the conformance tests.
- **§Interface-freeze gate (operationally defined):** "frozen after macOS" must be a concrete artifact + process, not a vibe. Define it as: a tagged commit of `src/viewy/backend/api.nim` + the interface section of `docs/native-backends.md`. Create an explicit **interface-freeze milestone bead** that all Windows beads depend on. Provide an **escape valve**: if Windows discovers a slot that pure-Nim COM genuinely cannot implement, it files an interface-change RFC bead that re-opens the gate — it does not edit `api.nim` freely. State the adjudication.
- **§ORC memory model (reconcile — do not introduce a second model):** `docs/threading.md` + `handoff.nim` establish a STRICT invariant: no Nim-managed closure/string/seq/ref crosses the thread boundary — only C-heap `SharedBytes` via top-level `{.cdecl, gcsafe.}` callbacks. The Constraints' "`GC_ref`'d Nim objects" phrasing is a looser, *different* model; mixing them reintroduces exactly the bug `test_wv_handoff.nim` guards. State which model applies where (UI-thread scheme/menu callbacks vs. worker-thread emit/resolve), make "no managed type crosses threads" the binding invariant, and replace "runs under valgrind" with a measurable bar: `test_emit_stress` + a scheme-flood test pass under `--mm:orc -d:useMalloc` + valgrind with zero `definitely lost` and zero invalid reads on Linux CI.
- **§Window-lifecycle events are NET-NEW public API** — there is no `App.on`, `WindowEvent`, or window-event plumbing today (`src/viewy/events.nim` is backend→JS `emit` only). `app.on(WindowClose)` / `onWindowEvent` need their own type, their own cross-thread delivery from native close handlers (subject to the §ORC model), and their own conformance test. Give it a distinct bead — do NOT fold it into the menu-DSL bead.
- **§winim / C++-TU fallbacks need real timeboxes + decision beads:** (a) Windows pure-Nim COM environment creation — spike bead with a stated timebox (e.g. 3 days) and a binary acceptance ("succeeds on clean Win11 + Evergreen, else fall back to one retained C++ TU using v1's `WEBVIEW_MSWEBVIEW2_BUILTIN_IMPL`"). (b) winim — a measurement bead with a concrete size-budget threshold; default remains hand-written Win32+COM. The C++-TU fallback has CI/build-flag implications (it partially reintroduces the shim v2 removes) — note them.
- **§GTK4 conflict:** the plan targets GTK3 + webkit2gtk-4.1 only, but `cli/src/viewy_cli/doctor.nim` already probes `gtk4 + webkitgtk-6.0` for `-d:viewyGtk4`. Add a bead to reconcile: native Linux backend is GTK3-only; decide whether `-d:viewyGtk4` is retired, kept for lite, or errors under native, and reword doctor accordingly.
- **§CI is materially understated — these are SEPARATE beads, not one "update ci.yml":** (1) a **valgrind job** on Linux under `--mm:orc -d:useMalloc` — not installed/invoked in `ci.yml` today; needs apt install + a WebKitGTK suppressions file + xvfb (slow, leak-noisy). (2) assert the ubuntu runner's `libwebkit2gtk-4.1-dev` is **≥ 2.40** or the POST/range criteria silently can't be tested. (3) **macOS windowed tests don't run windowed today** — Tier-2 on macOS is new CI. (4) the windowed matrix roughly **doubles** (each windowed test × {lite,native} × 3 OS) — replicate the existing 120s watchdog for native. (5) build-output assertion beads in `cli/tests` for macOS codesign + Info.plist and Windows PerMonitorV2 manifest (mirror the existing binary-size assertion). (6) Linux hosted CI has no SNI host, so the *positive* tray path is never CI-tested on Linux — document that gap explicitly.
- **§Decompose the monolithic native phases:** each native phase exceeds the <750-LOC atomic-bead budget if emitted whole. Instruct the graph generator to split each native backend into per-file/per-feature beads — FFI bindings (Linux: `gtk_ffi`/`webkitgtk_ffi`; Windows: `win32`/`com`/`webview2`) → window+webview lifecycle → IPC/bind + init-script (the §ORC GC hazard) → scheme handler → menus → tray — and to encode the within-phase ordering (window → IPC → scheme → menus → tray, per Constraints). Include RPC-envelope-parity and `runtime_js` bind→`window.<name>` Promise-parity as explicit sub-beads (native backends generate the JS bridge differently than `webview_bind`, so `docs/protocol.md` shapes and the injected `__viewy` runtime must be hand-reproduced per backend and asserted).
- **§Housekeeping beads (currently missing):** both `viewy.nimble` and `cli/viewy_cli.nimble` are `0.1.0` and `CHANGELOG.md` is `0.1.0 - Draft` — a backend rewrite + 3 features is at least a 0.2.0 (breaking) bump. Add beads for: nimble version bump (both packages), CHANGELOG 0.2.0 section, migration-guide entry, and updating `docs/release-checklist.md` (still pins webview/webview + WebView2 versions). Add a **WebView2 COM ABI pin** bead: the hand-written COM interfaces target a specific WebView2 SDK revision — keep `vendor/webview2/PIN` authoritative for both lite (C++ builtin impl) and the native COM declarations.

---

## File Reservation Planning

For each major work area, note the file patterns that will need exclusive reservation:

```bash
# Backend interface (high contention — everything depends on it):
#   src/viewy/backend/api.nim, src/viewy/backend/select.nim
# Linux native:   src/viewy/backend/native/linux/**
# macOS native:   src/viewy/backend/native/darwin/**
# Windows native: src/viewy/backend/native/windows/**
# Asset pipeline: src/viewy/assets.nim, src/viewy/assets_served.nim
# CLI:            cli/src/viewy_cli/{assets_gen,build,dev,doctor,config}.nim
# Conformance:    tests/** (parameterized suite — coordinate to avoid churn)
# Lite (frozen):  src/viewy/backend/lite/** (bugfix-only)
```

This helps agents claim appropriate file surfaces when they start work.

---

## Verification Steps

After generating the script:

1. **Run it**: `chmod +x setup-beads.sh && ./setup-beads.sh`
2. **Check ready work**: `bd ready` should show initial analysis/prep tasks

---

## Completeness Checklist

Ensure your task graph includes:

- [ ] Analysis of current implementation in affected areas
- [ ] Characterization tests for existing behavior
- [ ] Feature flag or gradual rollout mechanism (if applicable)
- [ ] Core implementation broken into small units
- [ ] Unit tests for new/changed code
- [ ] Integration tests for affected workflows
- [ ] Regression testing plan
- [ ] Documentation updates
- [ ] Migration scripts (if data changes)
- [ ] Rollback plan
- [ ] Cleanup tasks for post-rollout
- [ ] Clear dependency chains with no cycles
