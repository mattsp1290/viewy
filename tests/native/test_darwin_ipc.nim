when not defined(macosx):
  echo "skipped darwin native IPC: non-macOS host"
else:
  import std/os

  import viewy/backend/api
  import viewy/backend/native/darwin/backend
  import viewy/runtime_js

  let nativeBackend = newBackend()

  var
    windowHandle: BackendHandle
    reportSeen = false
    timeoutSeen = false
    seenReady = false
    seenReadyId = ""
    seenReadyArgs = ""
    seenLate = false
    unbindChecked = false
    doneMessage = ""

  proc resolveDone(h: BackendHandle; id: string) {.gcsafe.} =
    {.cast(gcsafe).}:
      newBackend().resolve(h, id, true, "\"done\"")

  proc dispatchResolveDone(h: BackendHandle; id: string) {.gcsafe.} =
    {.cast(gcsafe).}:
      newBackend().dispatchResolve(h, id, true, "\"dispatch\"")

  proc rejectValueError(h: BackendHandle; id: string) {.gcsafe.} =
    {.cast(gcsafe).}:
      newBackend().resolve(h, id, false,
        """{"error":{"message":"ValueError","type":"ValueError"}}""")

  proc resolveVoid(h: BackendHandle; id: string) {.gcsafe.} =
    {.cast(gcsafe).}:
      newBackend().resolve(h, id, true, "")

  proc terminate(h: BackendHandle) {.gcsafe.} =
    {.cast(gcsafe).}:
      newBackend().dispatchTerminate(h)

  proc timeoutThread() {.thread, gcsafe.} =
    sleep(5000)
    {.cast(gcsafe).}:
      if not reportSeen:
        timeoutSeen = true
        terminate(windowHandle)

  proc runIpcSmoke() =
    let h = nativeBackend.create(false)
    windowHandle = h
    nativeBackend.init(h, viewyRuntimeJs)

    nativeBackend.bindFn(h, "ready", proc(id, jsonArgs: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        seenReady = true
        seenReadyId = id
        seenReadyArgs = jsonArgs
      resolveDone(h, id)
    )
    nativeBackend.bindFn(h, "fail", proc(id, jsonArgs: string) {.gcsafe.} =
      discard jsonArgs
      rejectValueError(h, id)
    )
    nativeBackend.bindFn(h, "voidResult", proc(id,
        jsonArgs: string) {.gcsafe.} =
      discard jsonArgs
      resolveVoid(h, id)
    )
    nativeBackend.bindFn(h, "deferred", proc(id,
        jsonArgs: string) {.gcsafe.} =
      discard jsonArgs
      dispatchResolveDone(h, id)
    )
    nativeBackend.bindFn(h, "late", proc(id, jsonArgs: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        seenLate = true
      doAssert jsonArgs == """["after-load"]"""
      {.cast(gcsafe).}:
        newBackend().resolve(h, id, true, "\"late\"")
    )
    nativeBackend.bindFn(h, "removeLate", proc(id,
        jsonArgs: string) {.gcsafe.} =
      discard jsonArgs
      {.cast(gcsafe).}:
        newBackend().unbind(h, "late")
        unbindChecked = true
        newBackend().resolve(h, id, true, "\"removed\"")
    )
    nativeBackend.bindFn(h, "done", proc(id, jsonArgs: string) {.gcsafe.} =
      discard id
      {.cast(gcsafe).}:
        reportSeen = true
        if jsonArgs != "[]":
          doneMessage = jsonArgs
      terminate(h)
    )

    nativeBackend.setHtml(h, """
<!doctype html>
<script>
window.addEventListener("load", function() {
  Promise.resolve().then(function() {
    if (!window.__viewy || typeof window.__viewy.call !== "function") {
      throw new Error("missing runtime");
    }
    return window.ready("ok");
  }).then(function(value) {
    if (value !== "done") throw new Error("unexpected ready value");
    return window.late("after-load");
  }).then(function(value) {
    if (value !== "late") throw new Error("unexpected late value");
    return window.__viewy.call("fail");
  }).then(function() {
    throw new Error("expected rejection");
  }).catch(function(error) {
    if (!error || !error.error || error.error.type !== "ValueError") throw new Error("bad rejection");
    return window.__viewy.call("voidResult");
  }).then(function(value) {
    if (value !== undefined) throw new Error("expected undefined");
    return window.__viewy.call("deferred");
  }).then(function(value) {
    if (value !== "dispatch") throw new Error("bad dispatch resolve");
    return window.removeLate();
  }).then(function(value) {
    if (value !== "removed") throw new Error("bad unbind result");
    setTimeout(function() {
      try {
        if (typeof window.late !== "undefined") throw new Error("late still bound");
        window.done();
      } catch (error) {
        window.done(String(error && error.message || error));
      }
    }, 20);
  }).catch(function(error) {
    window.done(String(error && error.message || error));
  });
});
</script>
""")

    var timeout: Thread[void]
    createThread(timeout, timeoutThread)
    nativeBackend.run(h)
    nativeBackend.destroy(h)
    joinThread(timeout)

  if getEnv("VIEWY_NATIVE_DARWIN_IPC") == "1":
    runIpcSmoke()
    doAssert not timeoutSeen, "native macOS IPC parity timed out: " & doneMessage
    doAssert reportSeen
    doAssert doneMessage.len == 0, doneMessage
    doAssert seenReady
    doAssert seenReadyId.len > 0
    doAssert seenReadyArgs == """["ok"]"""
    doAssert seenLate
    doAssert unbindChecked

  echo "ok: darwin native IPC declarations"
