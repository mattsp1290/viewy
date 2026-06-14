import viewy

let event = WindowEvent(kind: weClose)
doAssert event.kind == weClose

let handler: WindowEventHandler =
  proc(event: WindowEvent) {.gcsafe.} =
    doAssert event.kind == weResize

handler(WindowEvent(kind: weResize, width: 800, height: 600))

echo "ok: window event root exports"
