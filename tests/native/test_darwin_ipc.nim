when not defined(macosx):
  echo "skipped darwin native IPC: non-macOS host"
else:
  import std/[locks, os]

  import viewy/backend/api
  import viewy/backend/native/darwin/backend
  import viewy/runtime_js

  let nativeBackend = newBackend()

  var
    stateLock: Lock
    windowHandle: BackendHandle
    reportSeen = false
    timeoutSeen = false
    seenReady = false
    seenReadyId = ""
    seenReadyArgs = ""
    seenCallArgs = false
    seenLate = false
    unbindChecked = false
    unbindReloadChecked = false
    workerResolveReturned = false
    doneMessage = ""

  type ResolvePayload = object
    handle: BackendHandle
    len: int
    data: ptr UncheckedArray[char]

  initLock(stateLock)

  proc resolveDone(h: BackendHandle; id: string) {.gcsafe.} =
    {.cast(gcsafe).}:
      newBackend().resolve(h, id, true, "\"done\"")

  proc newResolvePayload(h: BackendHandle; id: string): ptr ResolvePayload =
    result = cast[ptr ResolvePayload](allocShared0(sizeof(ResolvePayload)))
    doAssert result != nil
    result.handle = h
    result.len = id.len
    result.data = cast[ptr UncheckedArray[char]](allocShared0(id.len + 1))
    doAssert result.data != nil
    if id.len > 0:
      copyMem(addr result.data[0], unsafeAddr id[0], id.len)

  proc workerResolve(data: pointer) {.thread, gcsafe.} =
    let payload = cast[ptr ResolvePayload](data)
    var id = newString(payload.len)
    if payload.len > 0:
      copyMem(addr id[0], addr payload.data[0], payload.len)
    deallocShared(payload.data)
    let h = payload.handle
    deallocShared(payload)
    newBackend().dispatchResolve(h, id, true, "\"dispatch\"")
    {.cast(gcsafe).}:
      acquire(stateLock)
      workerResolveReturned = true
      release(stateLock)

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
      acquire(stateLock)
      let shouldTerminate = not reportSeen
      if shouldTerminate:
        timeoutSeen = true
      release(stateLock)
      if shouldTerminate:
        terminate(windowHandle)

  proc runIpcSmoke() =
    let h = nativeBackend.create(false)
    windowHandle = h
    nativeBackend.init(h, viewyRuntimeJs)

    nativeBackend.bindFn(h, "ready", proc(id, jsonArgs: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        acquire(stateLock)
        seenReady = true
        seenReadyId = id
        seenReadyArgs = jsonArgs
        release(stateLock)
      resolveDone(h, id)
    )
    nativeBackend.bindFn(h, "callArgs", proc(id,
        jsonArgs: string) {.gcsafe.} =
      doAssert jsonArgs == """["via-call",42]"""
      {.cast(gcsafe).}:
        acquire(stateLock)
        seenCallArgs = true
        release(stateLock)
        newBackend().resolve(h, id, true, "\"args\"")
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
        acquire(stateLock)
        seenLate = true
        release(stateLock)
      doAssert jsonArgs == """["after-load"]"""
      {.cast(gcsafe).}:
        newBackend().resolve(h, id, true, "\"late\"")
    )
    nativeBackend.bindFn(h, "removeLate", proc(id,
        jsonArgs: string) {.gcsafe.} =
      discard id
      discard jsonArgs
      {.cast(gcsafe).}:
        newBackend().unbind(h, "late")
        acquire(stateLock)
        unbindChecked = true
        release(stateLock)
        newBackend().setHtml(h, """
<!doctype html>
<script>
window.__viewyLateAfterReload = typeof window.late;
window.addEventListener("load", function() {
  window.done(window.__viewyLateAfterReload);
});
</script>
""")
    )
    nativeBackend.bindFn(h, "done", proc(id, jsonArgs: string) {.gcsafe.} =
      discard id
      {.cast(gcsafe).}:
        acquire(stateLock)
        reportSeen = true
        if jsonArgs == """["undefined"]""":
          unbindReloadChecked = true
        elif jsonArgs != "[]":
          doneMessage = jsonArgs
        release(stateLock)
      terminate(h)
    )

    var resolveWorker: Thread[pointer]
    createThread(resolveWorker, workerResolve, cast[pointer](
      newResolvePayload(h, "missing-worker")))
    joinThread(resolveWorker)

    nativeBackend.setHtml(h, """
<!doctype html>
<script>
window.__viewyDocStart = !!(window.__viewy && typeof window.__viewy.call === "function");
window.__viewyReadyDocStart = typeof window.ready === "function";
window.addEventListener("load", function() {
  Promise.resolve().then(function() {
    if (!window.__viewyDocStart || !window.__viewyReadyDocStart) {
      throw new Error("missing runtime");
    }
    return window.ready("ok");
  }).then(function(value) {
    if (value !== "done") throw new Error("unexpected ready value");
    return window.__viewy.call("callArgs", "via-call", 42);
  }).then(function(value) {
    if (value !== "args") throw new Error("bad call args result");
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
  }).catch(function(error) {
    window.done(String(error && error.message || error));
  });
});
</script>
""")

    var timeout: Thread[void]
    createThread(timeout, timeoutThread)
    nativeBackend.run(h)
    joinThread(timeout)
    nativeBackend.destroy(h)

  if getEnv("VIEWY_NATIVE_DARWIN_IPC") == "1":
    runIpcSmoke()
    acquire(stateLock)
    doAssert not timeoutSeen, "native macOS IPC parity timed out: " & doneMessage
    doAssert reportSeen
    doAssert doneMessage.len == 0, doneMessage
    doAssert seenReady
    doAssert seenReadyId.len > 0
    doAssert seenReadyArgs == """["ok"]"""
    doAssert seenCallArgs
    doAssert seenLate
    doAssert unbindChecked
    doAssert unbindReloadChecked
    doAssert workerResolveReturned
    release(stateLock)

  echo "ok: darwin native IPC declarations"
