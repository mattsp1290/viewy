import std/[json, locks, strutils]

import viewy
import viewy/backend/api

type
  Payload = object
    count: int
    label: string

let script = emitScript("ready", Payload(count: 3, label: "oak"))
doAssert script == """window.__viewy.emit("ready",{"count":3,"label":"oak"});"""

let quoted = emitScript("quote\"line\n", "payload\"value")
doAssert quoted.startsWith("window.__viewy.emit(")
doAssert quoted.endsWith(");")

let args = ("[" & quoted[
  "window.__viewy.emit(".len ..< quoted.len - 2
] & "]").parseJson()
doAssert args[0].getStr == "quote\"line\n"
doAssert args[1].getStr == "payload\"value"

var
  capturedLock: Lock
  capturedJs {.guard: capturedLock.}: string

initLock(capturedLock)

proc captureDispatchEval(h: BackendHandle; js: string) {.gcsafe.} =
  doAssert h == cast[BackendHandle](0x1)
  {.cast(gcsafe).}:
    withLock capturedLock:
      capturedJs = js

let fakeHandle = cast[BackendHandle](0x1)

proc worker() {.thread.} =
  let fakeBackend = Backend(dispatchEval: captureDispatchEval)
  emit(fakeBackend, fakeHandle, "worker", Payload(count: 5, label: "thread"))

var t: Thread[void]
createThread(t, worker)
joinThread(t)

withLock capturedLock:
  doAssert capturedJs == """window.__viewy.emit("worker",{"count":5,"label":"thread"});"""

deinitLock(capturedLock)

echo "ok: event emit script"
