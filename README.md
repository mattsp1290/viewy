# viewy

HTML Web View Desktop Apps for Nim — what Tauri is for Rust and Wails is
for Go. Nim backend, HTML/CSS/JS frontend, rendered in the OS-native
webview (WebKitGTK on Linux, WKWebView on macOS, Edge WebView2 on
Windows). No bundled Chromium.

> Pre-release package. The API is still settling; see
> [docs/viewy-spec.md](docs/viewy-spec.md) for the full design.

## Quickstart

Install the runtime library and CLI:

```bash
nimble install viewy
nimble install viewy_cli
```

Create and build a vanilla app:

```bash
viewy init my-app
cd my-app
npm ci
viewy build --release
```

Use `--template react` or `--template svelte` with `viewy init` for the
framework templates. `viewy build` runs the frontend build, generates
`src/viewy_assets.nim`, compiles the Nim app with `--mm:orc --threads:on`, and
prints the built binary path. On macOS it also writes a minimal `.app` bundle.

From a checkout before the first public publish:

```bash
nimble install
cd cli
nimble install
```

## Supported configuration

viewy is built and tested with:

```
nim c --mm:orc --threads:on src/viewy.nim
```

(This compiles the library root to document the supported flag set —
runnable apps are built through the CLI and `examples/` once they land.)

`--mm:orc --threads:on` is the supported memory-management/threading
configuration: all backend callbacks are `{.gcsafe.}` and cross-thread
work (e.g. `emit` from worker threads) routes through the backend's
`dispatch`. Other GC modes are untested.

- **Nim:** >= 2.0.0
- **Compilers:** gcc/clang; on Windows, MinGW-w64 or VCC (C++14 required
  for the WebView2 loader)

## Repository layout

```
viewy.nimble            # the library (jsony + zippy, nothing else)
src/viewy.nim           # re-exports the public API
src/viewy/              # app, rpc, events, assets modules
src/viewy/backend/      # backend abstraction + lite backend (lite/; wv/ shim)
cli/                    # viewy CLI package (init/dev/build)
examples/               # hello, todo
tests/
docs/                   # spec, protocol, architecture, limitations, release prep
```

## Development

```bash
nimble check                        # package metadata sanity
(cd cli && nimble check)            # CLI package metadata sanity
nim check --hints:off src/viewy.nim # type-check the library root
nimble test                         # run the test suite
nimble pretty                       # nimpretty over first-party Nim sources
```

A root `nim.cfg` with `--path:"src"` is committed so editor language
servers resolve `import viewy/...` the same way nimble does.

## License

MIT
