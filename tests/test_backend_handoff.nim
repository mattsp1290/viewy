## Windowed smoke check for the backend typed handoff path.

import std/os

import viewy/backend/api
import viewy/backend/select

var
  backend {.global.}: Backend
  h {.global.}: BackendHandle

proc worker() {.thread.} =
  {.cast(gcsafe).}:
    backend.dispatchEval(h, "void 0")
    backend.dispatchTerminate(h)

if getEnv("VIEWY_SKIP_WINDOWED") == "1":
  echo "skipped: VIEWY_SKIP_WINDOWED=1"
else:
  backend = newBackend()
  h = backend.create(false)
  backend.setHtml(h, "<html><body>viewy handoff stress</body></html>")

  var t: Thread[void]
  createThread(t, worker)
  backend.run(h)
  joinThread(t)
  backend.destroy(h)

  echo "ok: backend handoff"
