when not defined(linux):
  echo "skipped linux native backend: non-linux host"
else:
  import std/os

  import viewy/backend/api
  import viewy/backend/native/linux/backend
  import viewy/runtime_js

  let nativeBackend = newBackend()

  doAssert nativeBackend.create != nil
  doAssert nativeBackend.destroy != nil
  doAssert nativeBackend.run != nil
  doAssert nativeBackend.terminate != nil
  doAssert nativeBackend.dispatch != nil
  doAssert nativeBackend.dispatchEval != nil
  doAssert nativeBackend.dispatchResolve != nil
  doAssert nativeBackend.dispatchTerminate != nil
  doAssert nativeBackend.setTitle != nil
  doAssert nativeBackend.setSize != nil
  doAssert nativeBackend.navigate != nil
  doAssert nativeBackend.setHtml != nil
  doAssert nativeBackend.eval != nil
  doAssert nativeBackend.init != nil
  doAssert nativeBackend.bindFn != nil
  doAssert nativeBackend.unbind != nil
  doAssert nativeBackend.resolve != nil
  doAssert nativeBackend.caps == {}

  when defined(nimcheck):
    let handle = cast[BackendHandle](0x7)
    nativeBackend.setTitle(handle, "Viewy")
    nativeBackend.setSize(handle, 800, 600, whNone)
    nativeBackend.navigate(handle, "https://example.invalid")
    nativeBackend.setHtml(handle, "<html></html>")
    nativeBackend.eval(handle, "void 0")
    nativeBackend.init(handle, "globalThis.viewy = true")
    nativeBackend.bindFn(handle, "ready", proc(id,
        jsonArgs: string) {.gcsafe.} =
      discard id
      discard jsonArgs)
    nativeBackend.resolve(handle, "1", true, "\"ok\"")
    nativeBackend.dispatchEval(handle, "globalThis.viewyEval = true")
    nativeBackend.dispatchResolve(handle, "2", false,
      """{"error":{"message":"ValueError","type":"ValueError"}}""")
    nativeBackend.dispatch(handle, proc() {.gcsafe.} = discard)
    nativeBackend.dispatchTerminate(handle)

  proc terminateFromWorker(h: BackendHandle) {.thread.} =
    newBackend().dispatchTerminate(h)

  proc resolveDone(h: BackendHandle; id: string) {.gcsafe.} =
    {.cast(gcsafe).}:
      newBackend().resolve(h, id, true, "\"done\"")

  proc dispatchTerminate(h: BackendHandle) {.gcsafe.} =
    {.cast(gcsafe).}:
      newBackend().dispatchTerminate(h)

  proc smokeMainThreadTerminate() =
    let h = nativeBackend.create(false)
    nativeBackend.setTitle(h, "Viewy")
    nativeBackend.setSize(h, 320, 240, whMin)
    nativeBackend.setHtml(h, "<html><body>viewy native linux</body></html>")
    nativeBackend.dispatchTerminate(h)
    nativeBackend.run(h)
    nativeBackend.destroy(h)

  proc smokeWorkerTerminate() =
    let h = nativeBackend.create(false)
    nativeBackend.setTitle(h, "Viewy worker")
    nativeBackend.setSize(h, 360, 260, whFixed)
    nativeBackend.navigate(h, "about:blank")
    var worker: Thread[BackendHandle]
    createThread(worker, terminateFromWorker, h)
    nativeBackend.run(h)
    joinThread(worker)
    nativeBackend.destroy(h)

  proc smokeBindingRoundTrip() =
    var
      seen = false
      seenId = ""
      seenArgs = ""
    let h = nativeBackend.create(false)
    nativeBackend.init(h, viewyRuntimeJs)
    nativeBackend.bindFn(h, "ready", proc(id, jsonArgs: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        seen = true
        seenId = id
        seenArgs = jsonArgs
      resolveDone(h, id)
    )
    nativeBackend.bindFn(h, "done", proc(id, jsonArgs: string) {.gcsafe.} =
      discard id
      discard jsonArgs
      dispatchTerminate(h)
    )
    nativeBackend.setHtml(h, """
<!doctype html>
<script>
window.ready("ok").then(function(value) {
  if (value !== "done") throw new Error("unexpected value");
  return window.done();
}).catch(function(error) {
  window.done(String(error && error.message || error));
});
</script>
""")
    nativeBackend.run(h)
    nativeBackend.destroy(h)
    doAssert seen
    doAssert seenId.len > 0
    doAssert seenArgs == """["ok"]"""

  if getEnv("VIEWY_NATIVE_LINUX_SMOKE") == "1":
    smokeMainThreadTerminate()
    smokeWorkerTerminate()
    smokeBindingRoundTrip()

  echo "ok: linux native backend declarations"
