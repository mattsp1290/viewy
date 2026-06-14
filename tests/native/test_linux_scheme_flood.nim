when not defined(linux):
  echo "skipped linux native scheme flood: non-linux host"
else:
  import std/[json, os]

  import viewy/assets
  import viewy/backend/api
  import viewy/backend/native/linux/backend
  import viewy/backend/native/linux/gtk_ffi
  import zippy

  const
    fetchCount = 120
    indexHtml = """
<!doctype html>
<script>
(async function () {
  const report = { ok: false, count: 0 };
  try {
    for (let i = 0; i < 120; i++) {
      const response = await fetch("/assets/app.js?i=" + i);
      const text = await response.text();
      if (response.status !== 200 || text !== "export const value = 42;") {
        report.badStatus = response.status;
        report.badText = text;
        break;
      }
      report.count++;
    }
    const ranged = await fetch("/assets/app.js", {
      headers: { "Range": "bytes=7-11" }
    });
    report.rangeStatus = ranged.status;
    report.rangeText = await ranged.text();
    report.ok = report.count === 120 &&
      report.rangeStatus === 206 &&
      report.rangeText === "const";
  } catch (error) {
    report.error = String(error && error.message || error);
  }
  await window.report(JSON.stringify(report));
})();
</script>
"""
    appJs = "export const value = 42;"

  var
    nativeBackend = newBackend()
    windowHandle: BackendHandle
    reportSeen = false
    reportJson = ""
    assetRequests = 0
    timeoutSeen = false

  let tableHandler: AssetHandler = assetTableHandler([
    AssetTableItem(
      path: "/index.html",
      contentType: "text/html; charset=utf-8",
      etag: "\"viewy-flood\"",
      bytes: indexHtml,
      gzipBytes: compress(indexHtml),
    ),
    AssetTableItem(
      path: "/assets/app.js",
      contentType: "text/javascript; charset=utf-8",
      etag: "\"viewy-flood\"",
      bytes: appJs,
      gzipBytes: compress(appJs),
    ),
  ])

  proc schemeHandler(request: AssetRequest): AssetResponse {.gcsafe.} =
    if request.path == "/assets/app.js":
      {.cast(gcsafe).}:
        assetRequests.inc
    {.cast(gcsafe).}:
      tableHandler(request)

  proc reportCallback(id, jsonArgs: string) {.gcsafe.} =
    {.cast(gcsafe).}:
      let args = parseJson(jsonArgs)
      if args.len == 1:
        reportSeen = true
        reportJson = args[0].getStr
      nativeBackend.dispatchResolve(windowHandle, id, true, "true")
      nativeBackend.dispatchTerminate(windowHandle)

  proc timeoutCallback(data: pointer): GBoolean {.cdecl, gcsafe.} =
    discard data
    {.cast(gcsafe).}:
      timeoutSeen = true
      nativeBackend.dispatchTerminate(windowHandle)
    gFalse

  if getEnv("VIEWY_NATIVE_LINUX_SCHEME_FLOOD") == "1":
    doAssert capScheme in nativeBackend.caps
    let h = nativeBackend.create(false)
    windowHandle = h
    nativeBackend.bindFn(h, "report", reportCallback)
    nativeBackend.registerScheme(h, "viewy", schemeHandler)
    nativeBackend.navigate(h, "viewy://flood/")
    discard gTimeoutAdd(10000, timeoutCallback, nil)
    nativeBackend.run(h)
    nativeBackend.destroy(h)

    doAssert not timeoutSeen, "native Linux scheme flood timed out: " & reportJson
    doAssert reportSeen
    let report = parseJson(reportJson)
    doAssert report["ok"].getBool, reportJson
    doAssert report["count"].getInt == fetchCount
    doAssert assetRequests == fetchCount + 1

  echo "ok: linux native scheme flood declarations"
