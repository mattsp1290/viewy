## Minimal hosted-runner webview smoke.
##
## This intentionally does only create -> dispatch(terminate) -> run -> destroy.

import viewy/backend/wv/backend

let b = newBackend()
let h = b.create(false)
dispatchTerminate(h)
b.run(h)
b.destroy(h)

echo "ok: webview window smoke"
