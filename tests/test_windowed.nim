import std/[json, os]

import jsony

import viewy/backend/api
import viewy/backend/select
import viewy/rpc
import viewy/runtime_js

expose windowAdd(a, b: int): int =
  a + b

proc binding(name: string): RpcBinding =
  for item in bindings():
    if item.name == name:
      return item
  raise newException(ValueError, "missing binding: " & name)

var
  backend {.global.}: Backend
  windowHandle {.global.}: BackendHandle
  reportSeen {.global.}: bool
  reportJson {.global.}: string

proc windowAddCallback(id, jsonArgs: string) {.gcsafe.} =
  {.cast(gcsafe).}:
    let reply = binding("windowAdd").call(id, jsonArgs)
    backend.dispatchResolve(windowHandle, id, reply.ok, reply.json)

proc reportCallback(id, jsonArgs: string) {.gcsafe.} =
  {.cast(gcsafe).}:
    let args = jsonArgs.fromJson(seq[string])
    if args.len == 1:
      reportSeen = true
      reportJson = args[0]
      backend.dispatchResolve(windowHandle, id, true, "true")
    else:
      backend.dispatchResolve(windowHandle, id, false,
        """{"error":{"message":"ValueError","type":"ValueError"}}""")
    backend.dispatchTerminate(windowHandle)

if getEnv("VIEWY_SKIP_WINDOWED") == "1":
  echo "skipped windowed runtime RPC: VIEWY_SKIP_WINDOWED=1"
else:
  backend = newBackend()
  let h = backend.create(false)
  windowHandle = h
  reportSeen = false
  reportJson = ""

  backend.setTitle(h, "viewy windowed runtime RPC test")
  backend.init(h, viewyRuntimeJs)
  backend.bindFn(h, "windowAdd", windowAddCallback)
  backend.bindFn(h, "report", reportCallback)
  backend.setHtml(h, """
<!doctype html>
<meta charset="utf-8">
<script>
(function () {
  var settled = false;
  function finish(report) {
    if (settled) return;
    settled = true;
    window.report(JSON.stringify(report));
  }
  setTimeout(function () {
    finish({ ok: false, timeout: true });
  }, 5000);
  Promise.resolve().then(async function () {
    var report = { ok: false };
    report.runtime = !!(window.__viewy && typeof window.__viewy.call === "function");
    report.value = await window.__viewy.call("windowAdd", 20, 22);
    report.ok = report.runtime && report.value === 42;
    finish(report);
  }).catch(function (error) {
    finish({
      ok: false,
      error: String(error && error.message || error)
    });
  });
})();
</script>
""")

  backend.run(h)
  backend.destroy(h)

  doAssert reportSeen
  let report = parseJson(reportJson)
  doAssert report["ok"].getBool
  doAssert report["runtime"].getBool
  doAssert report["value"].getInt == 42

  echo "ok: windowed runtime RPC"
