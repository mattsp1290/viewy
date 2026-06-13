## Unmanaged cross-thread payload handoff for the lite backend.

import ./ffi

proc cMalloc(size: csize_t): pointer {.importc: "malloc", header: "<stdlib.h>".}
proc cFree(p: pointer) {.importc: "free", header: "<stdlib.h>".}

type
  WvHandoffError* = object of CatchableError
    ## Raised when a typed lite backend handoff cannot be queued.

  HandoffKind = enum
    hkEval
    hkResolve
    hkTerminate

  SharedBytes = object
    len: int
    data: ptr UncheckedArray[char]

  HandoffPayload = object
    kind: HandoffKind
    ok: bool
    a: SharedBytes
    b: SharedBytes

proc alloc0(size: Natural): pointer =
  result = cMalloc(csize_t(size))
  if result != nil:
    zeroMem(result, size)

proc dealloc(p: pointer) {.gcsafe.} =
  cFree(p)

proc free(bytes: var SharedBytes) {.gcsafe.} =
  if bytes.data != nil:
    dealloc(bytes.data)
    bytes.data = nil
  bytes.len = 0

proc initSharedBytes(value: string): SharedBytes =
  result.len = value.len
  result.data = cast[ptr UncheckedArray[char]](alloc0(value.len + 1))
  if result.data == nil:
    raise newException(WvHandoffError, "viewy handoff allocation failed")
  if value.len > 0:
    copyMem(addr result.data[0], unsafeAddr value[0], value.len)

proc toString(bytes: SharedBytes): string =
  result = newString(bytes.len)
  if bytes.len > 0:
    copyMem(addr result[0], addr bytes.data[0], bytes.len)

proc freePayload(payload: ptr HandoffPayload) {.gcsafe.} =
  if payload != nil:
    payload.a.free()
    payload.b.free()
    dealloc(payload)

proc newPayload(kind: HandoffKind; a: string; b = "";
    ok = false): ptr HandoffPayload =
  result = cast[ptr HandoffPayload](alloc0(sizeof(HandoffPayload)))
  if result == nil:
    raise newException(WvHandoffError, "viewy handoff allocation failed")

  try:
    result.kind = kind
    result.ok = ok
    result.a = initSharedBytes(a)
    result.b = initSharedBytes(b)
  except CatchableError:
    freePayload(result)
    raise

proc runHandoff(w: Webview; arg: pointer) {.cdecl, gcsafe.} =
  var payload = cast[ptr HandoffPayload](arg)
  if payload == nil:
    return

  try:
    let kind = payload.kind
    let ok = payload.ok
    let a = payload.a.toString()
    let b = payload.b.toString()
    freePayload(payload)
    payload = nil

    case kind
    of hkEval:
      discard webviewEval(w, a.cstring)
    of hkResolve:
      let status = if ok: cint(0) else: cint(1)
      discard webviewReturn(w, a.cstring, status, b.cstring)
    of hkTerminate:
      discard webviewTerminate(w)
  except CatchableError:
    freePayload(payload)

proc dispatchPayload(w: Webview; payload: ptr HandoffPayload) =
  let err = webviewDispatch(w, runHandoff, payload)
  if err != wvOk:
    freePayload(payload)
    raise newException(WvHandoffError, "webview_dispatch failed: " & $err)

proc dispatchEval*(w: Webview; js: string) =
  ## Schedule JavaScript evaluation with only unmanaged bytes crossing threads.
  dispatchPayload(w, newPayload(hkEval, js))

proc dispatchResolve*(w: Webview; id: string; ok: bool; jsonResult: string) =
  ## Schedule webview_return with only unmanaged bytes crossing threads.
  dispatchPayload(w, newPayload(hkResolve, id, jsonResult, ok))

proc dispatchTerminate*(w: Webview) =
  ## Schedule termination through the same unmanaged handoff callback path.
  dispatchPayload(w, newPayload(hkTerminate, ""))
