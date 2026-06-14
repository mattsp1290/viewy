when not defined(windows):
  echo "skipped windows backend lifecycle: non-Windows host"
else:
  import viewy/backend/native/windows/backend
  import viewy/backend/api

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
    var handle: BackendHandle
    if handle != nil:
      nativeBackend.setTitle(handle, "Viewy")
      nativeBackend.setSize(handle, 800, 600, whNone)
      nativeBackend.navigate(handle, "https://example.test/")
      nativeBackend.setHtml(handle, "<!doctype html><title>Viewy</title>")
      nativeBackend.init(handle, "window.__viewyInit = true;")
      nativeBackend.eval(handle, "window.__viewyEval = true;")
      nativeBackend.dispatchEval(handle, "window.__viewyDispatch = true;")
      nativeBackend.dispatchResolve(handle, "1", true, "{}")
      nativeBackend.dispatchTerminate(handle)
      nativeBackend.terminate(handle)

  echo "ok: windows backend lifecycle declarations"
