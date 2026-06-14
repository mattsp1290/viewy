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
  doAssert nativeBackend.registerSchemeImpl != nil
  doAssert capScheme in nativeBackend.caps
  doAssert capWindowVisibility in nativeBackend.caps
  doAssert nativeBackend.showWindowImpl != nil
  doAssert nativeBackend.hideWindowImpl != nil
  if capTray in nativeBackend.caps:
    doAssert nativeBackend.trayCreateImpl != nil
    doAssert nativeBackend.trayUpdateImpl != nil
    doAssert nativeBackend.trayDestroyImpl != nil
  else:
    doAssert nativeBackend.trayCreateImpl == nil
    doAssert nativeBackend.trayUpdateImpl == nil
    doAssert nativeBackend.trayDestroyImpl == nil

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
    nativeBackend.hideWindowImpl(handle)
    nativeBackend.showWindowImpl(handle)
    if capTray in nativeBackend.caps:
      nativeBackend.trayCreateImpl(handle, TrayOptions(
        id: "main",
        tooltip: "Viewy",
        iconPath: "viewy",
        menu: @[MenuItem(id: "show", label: "Show", kind: miCommand,
          enabled: true)],
      ), proc(id: string) {.gcsafe.} = discard id)
      nativeBackend.trayUpdateImpl(handle, "main", TrayOptions(
        id: "main",
        tooltip: "Viewy updated",
        templateIconPath: "viewy-symbolic",
        menu: @[MenuItem(id: "quit", label: "Quit", kind: miCommand,
          enabled: true)],
      ))
      nativeBackend.trayDestroyImpl(handle, "main")

  proc terminateFromWorker(h: BackendHandle) {.thread.} =
    newBackend().dispatchTerminate(h)

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
      lateSeen = false
      unbindChecked = false
      doneMessage = ""
    let h = nativeBackend.create(false)
    nativeBackend.init(h, viewyRuntimeJs)
    nativeBackend.bindFn(h, "ready", proc(id, jsonArgs: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        seen = true
        seenId = id
        seenArgs = jsonArgs
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

    let h2 = nativeBackend.create(false)
    nativeBackend.init(h2, viewyRuntimeJs)
    nativeBackend.bindFn(h2, "fail", proc(id, jsonArgs: string) {.gcsafe.} =
      discard jsonArgs
      rejectValueError(h2, id)
    )
    nativeBackend.bindFn(h2, "voidResult", proc(id,
        jsonArgs: string) {.gcsafe.} =
      discard jsonArgs
      resolveVoid(h2, id)
    )
    nativeBackend.bindFn(h2, "deferred", proc(id,
        jsonArgs: string) {.gcsafe.} =
      discard jsonArgs
      dispatchResolveDone(h2, id)
    )
    nativeBackend.bindFn(h2, "done", proc(id, jsonArgs: string) {.gcsafe.} =
      discard id
      if jsonArgs != "[]":
        {.cast(gcsafe).}:
          doneMessage = jsonArgs
      dispatchTerminate(h2)
    )
    nativeBackend.setHtml(h2, """
<!doctype html>
<script>
window.addEventListener("load", function() {
  setTimeout(function() {
    window.late("after-load").then(function(value) {
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
  }, 20);
});
</script>
""")
    nativeBackend.bindFn(h2, "late", proc(id, jsonArgs: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        lateSeen = true
      doAssert jsonArgs == """["after-load"]"""
      {.cast(gcsafe).}:
        newBackend().resolve(h2, id, true, "\"late\"")
    )
    nativeBackend.bindFn(h2, "removeLate", proc(id,
        jsonArgs: string) {.gcsafe.} =
      discard jsonArgs
      {.cast(gcsafe).}:
        newBackend().unbind(h2, "late")
        unbindChecked = true
        newBackend().resolve(h2, id, true, "\"removed\"")
    )
    nativeBackend.run(h2)
    nativeBackend.destroy(h2)
    doAssert doneMessage.len == 0, doneMessage
    doAssert lateSeen
    doAssert unbindChecked

  if getEnv("VIEWY_NATIVE_LINUX_SMOKE") == "1":
    smokeMainThreadTerminate()
    smokeWorkerTerminate()
    smokeBindingRoundTrip()

  echo "ok: linux native backend declarations"
