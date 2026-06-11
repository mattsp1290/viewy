# viewy

HTML Web View Desktop Apps for Nim — what Tauri is for Rust and Wails is
for Go. Nim backend, HTML/CSS/JS frontend, rendered in the OS-native
webview (WebKitGTK on Linux, WKWebView on macOS, Edge WebView2 on
Windows). No bundled Chromium.

> Early scaffold — the public API is not implemented yet. See
> [docs/viewy-spec.md](docs/viewy-spec.md) for the full design.

## Supported configuration

viewy is built and tested with:

```
nim c --mm:orc --threads:on src/viewy.nim
```

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
src/viewy/backend/      # backend abstraction + webview/webview backend (wv/)
cli/                    # viewy CLI package (init/dev/build)
examples/               # hello, todo
tests/
docs/                   # spec, protocol, architecture, limitations
```

## Development

```bash
nimble check                        # package metadata sanity
nim check --hints:off src/viewy.nim # type-check the library root
nimble test                         # run the test suite
nimble pretty                       # nimpretty over src/ and tests/
```

A root `nim.cfg` with `--path:"src"` is committed so editor language
servers resolve `import viewy/...` the same way nimble does.

## License

MIT
