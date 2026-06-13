## Compile-time backend selection.

import viewy/backend/api

when selectedBackend == "lite":
  import viewy/backend/lite/backend
  export backend.newBackend
elif selectedBackend == "native":
  import viewy/backend/lite/backend
  export backend.newBackend
else:
  {.error: "unsupported -d:viewyBackend value; expected 'native' or 'lite'".}
