when not defined(linux):
  echo "skipped linux native backend: non-linux host"
else:
  import viewy/backend/api
  import viewy/backend/native/linux/backend

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
    nativeBackend.dispatch(handle, proc() {.gcsafe.} = discard)
    nativeBackend.dispatchTerminate(handle)

  echo "ok: linux native backend declarations"
