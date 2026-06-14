when not defined(windows):
  echo "skipped windows native ipc: non-Windows host"
else:
  import viewy/backend/api
  import viewy/backend/native/windows/backend
  import viewy/runtime_js

  let nativeBackend = newBackend()

  doAssert nativeBackend.bindFn != nil
  doAssert nativeBackend.unbind != nil
  doAssert nativeBackend.resolve != nil
  doAssert nativeBackend.init != nil

  proc readyCallback(id, jsonArgs: string) {.gcsafe.} =
    discard id
    doAssert jsonArgs == "[]"

  when defined(nimcheck):
    var h: BackendHandle
    if h != nil:
      nativeBackend.init(h, viewyRuntimeJs)
      nativeBackend.bindFn(h, "ready", readyCallback)
      nativeBackend.eval(h, "window.__viewy.call('ready')")
      nativeBackend.resolve(h, "1", true, "{}")
      nativeBackend.dispatchResolve(h, "2", false, "{\"message\":\"fail\"}")
      nativeBackend.unbind(h, "ready")

  echo "ok: windows native ipc declarations"
