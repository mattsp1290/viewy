## Windowed stress check for the webview typed handoff path.

import std/os

import viewy/backend/wv/backend

const dispatchCount = 1000

var h {.global.}: BackendHandle

proc worker() {.thread.} =
  for i in 0 ..< dispatchCount:
    dispatchEval(h, "void 0")
  dispatchTerminate(h)

if getEnv("VIEWY_SKIP_WINDOWED") == "1":
  echo "skipped: VIEWY_SKIP_WINDOWED=1"
else:
  let b = newBackend()
  h = b.create(false)
  b.setHtml(h, "<html><body>viewy handoff stress</body></html>")

  var t: Thread[void]
  createThread(t, worker)
  b.run(h)
  joinThread(t)
  b.destroy(h)

  echo "ok: ", dispatchCount, " webview handoffs"
