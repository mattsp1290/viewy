when not defined(windows):
  echo "skipped windows native scheme: non-Windows host"
else:
  import viewy/assets
  import viewy/backend/api
  import viewy/backend/native/windows/backend

  let nativeBackend = newBackend()
  doAssert capScheme in nativeBackend.caps
  doAssert nativeBackend.registerSchemeImpl != nil

  proc schemeHandler(request: AssetRequest): AssetResponse {.gcsafe.} =
    doAssert request.scheme == "viewy"
    assetResponse(200, "OK", "text/plain; charset=utf-8", "ok")

  when defined(nimcheck):
    var h: BackendHandle
    if h != nil:
      nativeBackend.registerScheme(h, "viewy", schemeHandler)
      nativeBackend.navigate(h, "viewy://app/")

  echo "ok: windows native scheme declarations"
