# viewy protocol

This document specifies the wire protocol used between JavaScript running in the
webview and Nim procedures registered with `viewy/rpc.expose`. It documents the
current runtime contract so TypeScript binding generation can be added later
without changing the protocol.

## Binding calls

Each exposed Nim proc is registered under its proc name. The webview binding
layer exposes that name to JavaScript as `window.<name>(...args)`, returning a
Promise.

Arguments are encoded as a positional JSON array:

```json
["world", 42, {"x": 4, "name": "oak"}]
```

The array length must exactly match the exposed proc arity. The Nim wrapper
deserializes each array element into the declared parameter type with jsony.
Malformed JSON, a wrong argument count, or a value that cannot be decoded as the
declared type returns a structured error response.

Parameter names are not part of the runtime call envelope. They are emitted only
in metadata for tooling.

## Results

Successful non-void results are serialized with jsony as a JSON value and passed
to `webview_return` with status `0`.

Examples:

```json
"hello world"
```

```json
7
```

```json
{"x":5,"name":"oak"}
```

A void result is encoded as the empty string. webview/webview treats an empty
binding result as JavaScript `undefined`.

## Errors

Failures reject the JavaScript Promise. The rejection payload is always a JSON
object with this shape:

```json
{
  "error": {
    "message": "ValueError",
    "type": "ValueError"
  }
}
```

The current implementation deliberately sanitizes caught Nim exceptions: both
`message` and `type` are the exception type name, not the original exception
message. That avoids leaking implementation details such as parser offsets or
private exception text.

Backends map `ok = false` to a non-zero `webview_return` status; the webview
backend uses status `1`.

## Async results

`expose` supports procs returning `std/asyncdispatch.Future[T]`. Runtime calls
use the same argument, success, and error envelopes as synchronous procs.

For async procs:

- the immediate `RpcReply` has `pending = true`;
- app wiring keeps the webview bind request id;
- when the future completes, the supplied resolver returns the final JSON value
  through the backend dispatch/resolve path;
- when the future raises, the resolver returns the same structured error
  envelope used by synchronous wrappers.

`Future[void]` resolves with the empty string, producing JavaScript
`undefined`.

Calling an async binding through the sync-only `RpcBinding.call` entry point is
an integration error. It returns a structured `ValueError` response rather than
starting the future.

## Events

Backend-to-JavaScript events are delivered by the injected `__viewy` runtime.
The backend event transport evaluates a call equivalent to:

```js
window.__viewy.emit(eventName, payload)
```

The event name is encoded as a JSON string literal. The payload is any
jsony-serialized JSON value. The JavaScript runtime dispatches the payload to
callbacks registered with `window.__viewy.on(eventName, callback)` and invokes
callbacks as `callback(payload, eventName)`.

The event envelope is intentionally minimal:

```json
{
  "event": "ready",
  "payload": {"count": 1}
}
```

The object above is the reserved logical shape for tooling. The transport may
inline it as JavaScript source instead of sending this exact object over a
separate channel.

Nim `emit` serializes on the calling thread and queues the final JavaScript
source through the backend typed eval handoff, so event emission is intended to
be callable from worker threads without moving GC-managed closures across
threads.

## Metadata

The runtime registry exposes metadata as JSON through `dumpBindingsJson()`. The
compile-time dump mode `-d:viewyDumpBindings` emits one metadata object per line
while compiling modules that use `expose`; consumers should parse it as
newline-delimited JSON.

Each metadata object has this shape:

```json
{
  "name": "asyncAdd",
  "params": [
    {"name": "a", "typ": "int"},
    {"name": "b", "typ": "int"}
  ],
  "returnType": "int",
  "async": true
}
```

Fields:

- `name`: exposed JavaScript binding name.
- `params`: ordered parameter metadata. Runtime calls still use positional args.
- `params[].name`: Nim parameter name as written in the `expose` signature.
- `params[].typ`: Nim type representation used by the macro.
- `returnType`: Nim return type representation exposed to tooling.
- `async`: `true` when the exposed return type is `Future[T]`; `returnType` is
  the unwrapped `T`.

Void return metadata uses `"returnType": "void"`. `Future[void]` uses
`"returnType": "void"` and `"async": true`.

The metadata schema is additive. Future tooling may add fields, but existing
fields should remain stable.

## Compatibility notes

- Runtime calls are positional and do not carry parameter names.
- All JSON serialization and deserialization uses jsony.
- Promise resolution maps to `webview_return` status `0`.
- Promise rejection maps to a non-zero `webview_return` status.
- Empty result strings represent JavaScript `undefined`.
- Metadata dump mode is NDJSON, not a JSON array.
