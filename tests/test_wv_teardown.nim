## Repeated WebView2 teardown smoke for handoff-triggered shutdown.

import std/os

import viewy/backend/wv/backend

const iterations = 3

var h {.global.}: BackendHandle

proc worker() {.thread.} =
  dispatchEval(h, "void 0")
  dispatchTerminate(h)

if getEnv("VIEWY_SKIP_WINDOWED") == "1":
  echo "skipped webview teardown: VIEWY_SKIP_WINDOWED=1"
else:
  for i in 0 ..< iterations:
    let b = newBackend()
    h = b.create(false)
    b.setHtml(h, "<html><body>viewy teardown</body></html>")

    var t: Thread[void]
    createThread(t, worker)
    b.run(h)
    joinThread(t)
    b.destroy(h)

  echo "ok: webview teardown"
