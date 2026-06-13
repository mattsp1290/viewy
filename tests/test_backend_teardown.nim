## Repeated backend teardown smoke for handoff-triggered shutdown.

import std/os

import viewy/backend/api
import viewy/backend/select

const iterations = 3

var
  backend {.global.}: Backend
  h {.global.}: BackendHandle

proc worker() {.thread.} =
  {.cast(gcsafe).}:
    backend.dispatchEval(h, "void 0")
    backend.dispatchTerminate(h)

if getEnv("VIEWY_SKIP_WINDOWED") == "1":
  echo "skipped backend teardown: VIEWY_SKIP_WINDOWED=1"
else:
  for i in 0 ..< iterations:
    backend = newBackend()
    h = backend.create(false)
    backend.setHtml(h, "<html><body>viewy teardown</body></html>")

    var t: Thread[void]
    createThread(t, worker)
    backend.run(h)
    joinThread(t)
    backend.destroy(h)

  echo "ok: backend teardown"
