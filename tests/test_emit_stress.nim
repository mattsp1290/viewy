import std/[json, os, strformat]

import jsony

import viewy
import viewy/backend/api
import viewy/backend/select
import viewy/runtime_js

const
  workerCount = 6
  eventsPerWorker = 40
  expectedEvents = workerCount * eventsPerWorker

type
  EventPayload = object
    worker: int
    index: int

  WorkerArgs = object
    worker: int

var
  appBackend {.global.}: Backend
  windowHandle {.global.}: BackendHandle
  reportSeen {.global.}: bool
  reportJson {.global.}: string
  doneSeen {.global.}: bool
  started {.global.}: bool
  threads {.global.}: array[workerCount, Thread[WorkerArgs]]
  args {.global.}: array[workerCount, WorkerArgs]

proc worker(args: WorkerArgs) {.thread.} =
  for i in 0 ..< eventsPerWorker:
    {.cast(gcsafe).}:
      appBackend.dispatchEval(windowHandle, emitScript("stress", EventPayload(
          worker: args.worker, index: i)))

proc reportCallback(id, jsonArgs: string) {.gcsafe.} =
  {.cast(gcsafe).}:
    let args = jsonArgs.fromJson(seq[string])
    if args.len == 1:
      reportSeen = true
      reportJson = args[0]
      appBackend.dispatchResolve(windowHandle, id, true, "true")
    else:
      appBackend.dispatchResolve(windowHandle, id, false,
        """{"error":{"message":"ValueError","type":"ValueError"}}""")

proc doneCallback(id, jsonArgs: string) {.gcsafe.} =
  {.cast(gcsafe).}:
    discard id
    discard jsonArgs
    doneSeen = true
    appBackend.dispatchTerminate(windowHandle)

proc readyCallback(id, jsonArgs: string) {.gcsafe.} =
  {.cast(gcsafe).}:
    discard jsonArgs
    if not started:
      started = true
      for i in 0 ..< workerCount:
        args[i] = WorkerArgs(worker: i)
        createThread(threads[i], worker, args[i])
    appBackend.dispatchResolve(windowHandle, id, true, "true")

if getEnv("VIEWY_SKIP_WINDOWED") == "1":
  echo "skipped emit stress: VIEWY_SKIP_WINDOWED=1"
else:
  appBackend = newBackend()
  let h = appBackend.create(false)
  windowHandle = h
  reportSeen = false
  reportJson = ""
  doneSeen = false
  started = false

  appBackend.setTitle(h, "viewy emit stress")
  appBackend.init(h, viewyRuntimeJs)
  appBackend.bindFn(h, "ready", readyCallback)
  appBackend.bindFn(h, "report", reportCallback)
  appBackend.bindFn(h, "done", doneCallback)
  appBackend.setHtml(h, fmt"""
<!doctype html>
<meta charset="utf-8">
<script>
(function () {{
  var expected = {expectedEvents};
  var seen = Object.create(null);
  var count = 0;
  var duplicates = 0;
  var invalid = 0;
  var settled = false;

  function finish(report) {{
    if (settled) return;
    settled = true;
    Promise.resolve(window.report(JSON.stringify(report))).then(function () {{
      window.done();
    }}, function () {{
      window.done();
    }});
  }}

  setTimeout(function () {{
    finish({{
      ok: false,
      timeout: true,
      count: count,
      expected: expected,
      duplicates: duplicates,
      invalid: invalid
    }});
  }}, 10000);

  window.__viewy.on("stress", function (payload) {{
    var worker = payload && payload.worker;
    var index = payload && payload.index;
    var key = worker + ":" + index;

    if (!Number.isInteger(worker) || !Number.isInteger(index)) {{
      invalid++;
      return;
    }}

    if (seen[key]) {{
      duplicates++;
      return;
    }}

    seen[key] = true;
    count++;
    if (count === expected) {{
      finish({{
        ok: duplicates === 0 && invalid === 0,
        count: count,
        expected: expected,
        duplicates: duplicates,
        invalid: invalid
      }});
    }}
  }});

  window.ready().catch(function (error) {{
    finish({{
      ok: false,
      readyError: String(error && error.message || error),
      count: count,
      expected: expected,
      duplicates: duplicates,
      invalid: invalid
    }});
  }});
}})();
</script>
""")

  appBackend.run(h)

  if started:
    for i in 0 ..< workerCount:
      joinThread(threads[i])

  appBackend.destroy(h)

  doAssert reportSeen
  doAssert doneSeen
  let report = parseJson(reportJson)
  doAssert report["ok"].getBool
  doAssert report["count"].getInt == expectedEvents
  doAssert report["expected"].getInt == expectedEvents
  doAssert report["duplicates"].getInt == 0
  doAssert report["invalid"].getInt == 0

  echo "ok: emit stress"
