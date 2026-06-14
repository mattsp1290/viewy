when not defined(linux):
  echo "skipped linux native scheme: non-linux host"
else:
  import std/[json, os, strutils]

  import viewy/assets
  import viewy/backend/api
  import viewy/backend/native/linux/backend
  import viewy/backend/native/linux/gtk_ffi
  import zippy

  proc header(request: AssetRequest; name: string): string =
    for header in request.headers:
      if cmpIgnoreCase(header.name, name) == 0:
        return header.value

  var
    nativeBackend = newBackend()
    windowHandle: BackendHandle
    reportSeen = false
    reportJson = ""
    echoQuery = ""
    echoBody = ""
    rangeSeen = false
    timeoutSeen = false

  const
    indexHtml = """
<!doctype html>
<script>
(async function () {
  const report = { ok: false };
  try {
    const script = await fetch("assets/app.js?v=1");
    report.scriptStatus = script.status;
    report.scriptType = script.headers.get("content-type");
    report.scriptText = await script.text();

    const spa = await fetch("/settings/profile", {
      headers: { "Accept": "text/html" }
    });
    report.spaStatus = spa.status;
    report.spaText = await spa.text();

    const missing = await fetch("/assets/missing.js");
    report.missingStatus = missing.status;

    const posted = await fetch("/echo?x=1", {
      method: "POST",
      headers: { "Content-Type": "text/plain" },
      body: "payload"
    });
    report.postStatus = posted.status;
    report.postText = await posted.text();

    const ranged = await fetch("/assets/app.js", {
      headers: { "Range": "bytes=0-5" }
    });
    report.rangeStatus = ranged.status;
    report.rangeHeader = ranged.headers.get("content-range");
    report.rangeEncoding = ranged.headers.get("content-encoding");
    report.rangeText = await ranged.text();

    report.ok = report.scriptStatus === 200 &&
      /text\/javascript/.test(report.scriptType || "") &&
      report.scriptText === "export const value = 42;" &&
      report.spaStatus === 200 &&
      report.spaText.indexOf("assets/app.js") >= 0 &&
      report.missingStatus === 404 &&
      report.postStatus === 200 &&
      report.postText === "x=1|payload|text/plain" &&
      report.rangeStatus === 206 &&
      report.rangeHeader === "bytes 0-5/24" &&
      report.rangeEncoding === null &&
      report.rangeText === "export";
  } catch (error) {
    report.error = String(error && error.message || error);
  }
  await window.report(JSON.stringify(report));
})();
</script>
"""
    appJs = "export const value = 42;"

  let tableHandler: AssetHandler = assetTableHandler([
    AssetTableItem(
      path: "/index.html",
      contentType: "text/html; charset=utf-8",
      etag: "\"viewy-native\"",
      bytes: indexHtml,
      gzipBytes: compress(indexHtml),
    ),
    AssetTableItem(
      path: "/assets/app.js",
      contentType: "text/javascript; charset=utf-8",
      etag: "\"viewy-native\"",
      bytes: appJs,
      gzipBytes: compress(appJs),
    ),
  ])

  proc schemeHandler(request: AssetRequest): AssetResponse {.gcsafe.} =
    if request.path == "/echo":
      {.cast(gcsafe).}:
        echoQuery = request.query
        echoBody = request.body
      return assetResponse(200, "OK", "text/plain; charset=utf-8",
        request.query & "|" & request.body & "|" &
        request.header("Content-Type"))
    if request.path == "/assets/app.js" and request.header("Range").len > 0:
      {.cast(gcsafe).}:
        rangeSeen = true
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

  if getEnv("VIEWY_NATIVE_LINUX_SCHEME") == "1":
    doAssert capScheme in nativeBackend.caps
    let h = nativeBackend.create(false)
    windowHandle = h
    nativeBackend.bindFn(h, "report", reportCallback)
    nativeBackend.registerScheme(h, "viewy", schemeHandler)
    nativeBackend.navigate(h, "viewy://app/")
    discard gTimeoutAdd(5000, timeoutCallback, nil)
    nativeBackend.run(h)
    nativeBackend.destroy(h)

    doAssert not timeoutSeen, "native Linux scheme conformance timed out: " &
      reportJson
    doAssert reportSeen
    let report = parseJson(reportJson)
    doAssert report["ok"].getBool, reportJson
    doAssert echoQuery == "x=1"
    doAssert echoBody == "payload"
    doAssert rangeSeen

  echo "ok: linux native scheme declarations"
