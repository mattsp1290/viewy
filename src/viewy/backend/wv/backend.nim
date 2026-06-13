## Deprecated compatibility shim for the old webview backend import path.
##
## New code should import `viewy/backend/lite/backend`. This module intentionally
## re-exports the lite backend so existing v1 code that imports
## `viewy/backend/wv/backend` continues to compile during the v2 migration.

{.warning: "viewy/backend/wv/backend is deprecated; import viewy/backend/lite/backend instead".}

import ../lite/backend

export backend
