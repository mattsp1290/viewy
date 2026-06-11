## Backend-to-JavaScript event emission.

import jsony

import viewy/backend/api

export jsony

proc emitScript*[T](event: string; payload: T): string =
  ## Return the JavaScript source used to deliver one event payload.
  ##
  ## The event name is encoded as a JSON string literal and the payload is
  ## encoded as a JSON value with jsony, so both can be safely inlined into the
  ## injected `window.__viewy.emit(event, payload)` call.
  "window.__viewy.emit(" & event.toJson() & "," & payload.toJson() & ");"

proc emit*[T](backend: Backend; h: BackendHandle; event: string;
    payload: T) {.gcsafe.} =
  ## Emit an event to JavaScript from the UI thread or a worker thread.
  ##
  ## This proc serializes the event and payload on the calling thread, then
  ## queues the final JavaScript source through the backend's typed unmanaged
  ## eval handoff. It does not capture Nim GC-managed closures across threads.
  backend.dispatchEval(h, emitScript(event, payload))
