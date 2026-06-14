# Test Tiers

The v1 suite is the lite/native backend conformance contract. Tests are grouped
by what they require from the host environment.

## Tier 1: Pure Logic

Runs headlessly everywhere and does not create a backend window.

- `test_app.nim`
- `test_app_dev.nim`
- `test_accel.nim`
- `test_assets.nim`
- `test_assets_generated.nim`
- `test_assets_served.nim`
- `test_backend_api.nim`
- `test_backend_select.nim`
- `test_dump_bindings.nim`
- `test_events.nim`
- `test_rpc.nim`
- `test_rpc_dump.nim`
- `test_runtime_js.nim`
- `test_served_auth.nim`
- `test_scheme_routing.nim`
- `test_window_events.nim`
- `tviewy.nim`

### Native Compile Smokes

Compile-only platform FFI/glue checks. They skip or are CI-gated off-platform.

- `native/test_darwin_glue.nim`
- `native/test_darwin_backend.nim`
- `native/test_linux_gtk_ffi.nim`
- `native/test_linux_webkitgtk_ffi.nim`

## Tier 2: Real Backend Smoke

Runs against a real `newBackend()` and a real display. These tests are gated by
`VIEWY_SKIP_WINDOWED=1` for headless local runs and are compile-selected with
`-d:viewyBackend=lite|native`.

- `test_async_rpc.nim`
- `test_assets_single.nim`
- `test_backend_handoff.nim`
- `test_backend_teardown.nim`
- `test_emit_stress.nim`
- `native/test_darwin_ipc.nim`
- `native/test_darwin_scheme.nim`
- `native/test_linux_scheme.nim`
- `native/test_linux_scheme_flood.nim` (Valgrind-focused)
- `test_windowed.nim`
- `spike/window_smoke.nim`

## Tier 3: Manual QA

Manual native-backend QA is tracked outside the automated suite. The named owner
is [docs/qa-checklist.md](../docs/qa-checklist.md).
