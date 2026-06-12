# Served asset mode

Served mode is the optional production asset path for apps that cannot fit the
single-file `setHtml` model. It embeds the built frontend as a table of paths to
gzip-compressed bytes, starts a loopback-only HTTP server, and navigates the
webview to that server.

The default production path remains single-file embedded HTML. Served mode is a
tradeoff for apps that need normal URL routing or separate static assets.

## Server choice

Use `std/asynchttpserver`, not a hand-rolled HTTP/1.1 parser.

The spec originally mentions `std/asynchttpdispatch`; that module does not
exist. The relevant stdlib module is `std/asynchttpserver`, backed by
`std/asyncdispatch`.

Reasons:

- Dependency footprint is the same. Both options can stay stdlib-only, and
  `zippy` is already pinned for served-mode asset compression.
- HTTP parsing, method handling, headers, and response formatting are not the
  differentiating value of viewy. Reimplementing them increases the chance of
  subtle security and compatibility bugs.
- The blocking webview loop stays on the main/UI thread. The HTTP server can run
  on a dedicated server thread with its own `asyncdispatch` loop, so it does not
  require pumping the webview loop or moving request callbacks through backend
  dispatch.
- Shutdown can be explicit: the server thread owns the `AsyncHttpServer`, polls
  a stop flag between `poll()` calls, closes the server, drains pending work for
  a short bounded interval, then joins before app teardown completes.

The callback must not touch the webview backend. It only reads served-mode state
owned by the server thread and returns HTTP responses. UI-facing operations
still use the backend handoff rules from `docs/threading.md`.

## Binding

Bind only to `127.0.0.1` with port `0`.

Startup flow:

1. Build served asset state from the generated table.
2. Generate a per-launch path prefix, a one-time document token, and a separate
   per-launch session token.
3. Start the server thread.
4. The server binds `127.0.0.1:0` and reports the selected port to the caller.
5. The app calls
   `navigate("http://127.0.0.1:<port>/<prefix>/?viewy_token=<token>")`.

Do not bind `localhost`; name resolution can include IPv6 or host-file behavior
that is broader than intended. Do not bind `0.0.0.0` or `::`.

The prefix should be unguessable and unique per launch. It scopes routes and the
session cookie away from unrelated loopback services on other ports, because
cookies are scoped by host and path, not by port.

## Authentication bootstrap

The first document navigation cannot rely on a cookie injected by page
JavaScript, because the page has not loaded yet. Served mode therefore uses an
HTTP-level two-step bootstrap.

The initial document URL carries a one-time query token:

```text
GET /<prefix>/?viewy_token=<one-time-token>
```

That query token is valid only for the document route. It must not authorize
assets, RPC routes, source maps, or any other route. After one successful use it
is consumed and replay attempts return `401`.

On success, the server consumes the one-time token and returns the document with
an HTTP session cookie:

```text
Set-Cookie: __viewy_session=<session-token>; Path=/<prefix>/; SameSite=Strict; HttpOnly
```

The response body must not rely on JavaScript to create the first session
credential. Browsers can discover stylesheet, preload, favicon, module, or image
subresources while parsing the document; those first asset requests must already
carry the cookie from the document response.

The returned document may include a tiny bootstrap script before app scripts to
remove the query token from the visible URL and verify the runtime origin:

```html
<script>
history.replaceState(null, "", location.pathname + location.hash);
</script>
```

After that bootstrap, normal app requests authenticate with either:

- cookie: `__viewy_session=<session-token>`
- bearer header: `Authorization: Bearer <session-token>`

The bearer form exists for headless tests and future tooling. The webview path
should use the HTTP-set cookie. JavaScript should not need to read the cookie,
so the cookie can be `HttpOnly`.

All non-document routes require the session credential and return `401` without
it. This includes static assets and any future HTTP-backed RPC endpoint. RPC
errors still use the structured protocol envelope from `docs/protocol.md`; auth
failures are transport failures and do not expose raw exception text.

## Routes

Minimum route set:

- `GET /<prefix>/` returns the app document when the one-time token is valid or
  a session credential is present.
- `GET /<prefix>/<asset-path>` returns a generated asset when the session
  credential is present.
- Future RPC-over-HTTP routes, if added, require the same session credential.

Unsupported methods return `405`. Missing paths return `404`. Unauthenticated
requests return `401` before route-specific detail is exposed.

Asset responses should set:

- `Content-Type` from the generated path metadata or extension fallback.
- `Content-Encoding: gzip` for compressed entries.
- `Cache-Control: no-store`, because assets are embedded in the current process
  and protected by per-launch credentials.

## Generated asset table

The served-mode generator should emit a module similar to the single-file
`viewy_assets` contract, but with an asset table:

```nim
type
  ServedAsset* = object
    path*: string
    contentType*: string
    gzipBytes*: string

const viewyServedAssets* = [
  ServedAsset(path: "/index.html", contentType: "text/html", gzipBytes: "..."),
]
const viewyServedDocumentPath* = "/index.html"
```

The implementation can adjust the exact Nim shape, but the generated data must
include path, content type, and gzip-compressed bytes. The server should build a
lookup table at startup so request handling is path based and does not scan the
asset list for every request.

## Threading and lifetime

The server thread owns:

- the `AsyncHttpServer`
- the asset lookup table
- the one-time document token state
- the session token

The UI thread owns:

- the webview backend handle
- app creation and destruction
- navigation to the served-mode URL

The only cross-thread data needed at startup is the selected port or startup
error. The only cross-thread data needed at shutdown is a stop signal and the
joined server thread result. Do not capture webview handles or backend procs in
HTTP callbacks.

Shutdown requirements:

1. Stop accepting new requests.
2. Close the bound server socket.
3. Let in-flight callbacks finish for a bounded interval.
4. Join the server thread before `run()` returns.

If the server fails to start, `run()` should fail before creating or navigating
the webview. If shutdown times out, prefer a clear error in tests; production
should still avoid touching a destroyed webview handle.

## Test surface

The served-mode implementation must expose a headless server entry point so CI
can test auth without opening a native window.

Required tests:

- server binds `127.0.0.1` and an ephemeral port;
- asset and RPC routes without credentials return `401`;
- document route with a valid one-time token returns `200` with a `Set-Cookie`
  header scoped to the launch prefix;
- replaying the one-time token returns `401`;
- asset and RPC routes with the session cookie or bearer token return `200`;
- shutdown closes the port and leaves no server thread running.
