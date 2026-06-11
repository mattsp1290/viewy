import std/[asyncdispatch, json, os]

import jsony
import viewy/backend/wv/backend
import viewy/rpc

proc delayedValue(value: int): Future[int] {.async.} =
  await sleepAsync(1)
  value

proc delayedFailure(): Future[string] {.async.} =
  await sleepAsync(1)
  raise newException(ValueError, "async secret")

expose asyncAdd(a, b: int): Future[int] =
  delayedValue(a + b)

expose asyncFail(): Future[string] =
  delayedFailure()

proc binding(name: string): RpcBinding =
  for item in bindings():
    if item.name == name:
      return item
  raise newException(ValueError, "missing binding: " & name)

var
  windowHandle {.global.}: BackendHandle
  windowDone {.global.}: bool
  windowReportJson {.global.}: string

proc pumpPending() {.gcsafe.} =
  for i in 0 ..< 20:
    discard i
    {.cast(gcsafe).}:
      poll(1)

proc resolveByDispatch(id: string; ok: bool; json: string) {.gcsafe.} =
  dispatchResolve(windowHandle, id, ok, json)

proc invokeRpc(name, id, jsonArgs: string) {.gcsafe.} =
  {.cast(gcsafe).}:
    let rpc = binding(name)
    let reply = rpc.callWithResolver(id, jsonArgs, resolveByDispatch)
    if reply.pending:
      pumpPending()
    else:
      dispatchResolve(windowHandle, id, reply.ok, reply.json)

proc asyncAddCallback(id, jsonArgs: string) {.gcsafe.} =
  invokeRpc("asyncAdd", id, jsonArgs)

proc asyncFailCallback(id, jsonArgs: string) {.gcsafe.} =
  invokeRpc("asyncFail", id, jsonArgs)

proc reportCallback(id, jsonArgs: string) {.gcsafe.} =
  {.cast(gcsafe).}:
    let args = jsonArgs.fromJson(seq[string])
    if args.len == 1:
      windowReportJson = args[0]
      windowDone = true
      dispatchResolve(windowHandle, id, true, "true")
    else:
      dispatchResolve(windowHandle, id, false,
        """{"error":{"message":"ValueError","type":"ValueError"}}""")
    dispatchTerminate(windowHandle)

var
  unitResolved = false
  unitId = ""
  unitOk = false
  unitJson = ""

proc captureResolve(id: string; ok: bool; json: string) =
  unitResolved = true
  unitId = id
  unitOk = ok
  unitJson = json

let unitReply = binding("asyncAdd").callWithResolver("unit-ok", "[4,6]",
    captureResolve)
doAssert unitReply.ok
doAssert unitReply.pending
while not unitResolved:
  poll(10)
doAssert unitId == "unit-ok"
doAssert unitOk
doAssert unitJson.fromJson(int) == 10

unitResolved = false
let unitFailure = binding("asyncFail").callWithResolver("unit-fail", "[]",
    captureResolve)
doAssert unitFailure.ok
doAssert unitFailure.pending
while not unitResolved:
  poll(10)
doAssert unitId == "unit-fail"
doAssert not unitOk
let failed = parseJson(unitJson)
doAssert failed["error"]["type"].getStr == "ValueError"
doAssert failed["error"]["message"].getStr == "ValueError"
doAssert failed["error"]["message"].getStr != "async secret"

if getEnv("VIEWY_SKIP_WINDOWED") == "1":
  echo "skipped windowed async RPC: VIEWY_SKIP_WINDOWED=1"
else:
  let b = newBackend()
  let h = b.create(false)
  windowHandle = h
  windowDone = false
  windowReportJson = ""

  b.bindFn(h, "asyncAdd", asyncAddCallback)
  b.bindFn(h, "asyncFail", asyncFailCallback)
  b.bindFn(h, "report", reportCallback)

  b.setHtml(h, """
<!doctype html>
<meta charset="utf-8">
<script>
(async function () {
  const report = { ok: false };
  try {
    report.value = await window.asyncAdd(2, 5);
    try {
      await window.asyncFail();
      report.rejectType = "missing";
    } catch (error) {
      report.rejectType = error && error.error && error.error.type;
      report.rejectMessage = error && error.error && error.error.message;
    }
    report.ok = report.value === 7 &&
      report.rejectType === "ValueError" &&
      report.rejectMessage === "ValueError";
  } catch (error) {
    report.unexpected = String(error && error.message || error);
  }
  await window.report(JSON.stringify(report));
})();
</script>
""")

  b.run(h)
  b.destroy(h)

  doAssert windowDone
  let report = parseJson(windowReportJson)
  doAssert report["ok"].getBool
  doAssert report["value"].getInt == 7
  doAssert report["rejectType"].getStr == "ValueError"
  doAssert report["rejectMessage"].getStr == "ValueError"

  echo "ok: async RPC window resolve/reject"
