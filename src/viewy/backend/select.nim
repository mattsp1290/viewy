## Compile-time backend selection.

import viewy/backend/api

when selectedBackend == "lite":
  import viewy/backend/lite/backend
  export backend.newBackend
elif selectedBackend == "native":
  template newBackend*(): Backend =
    {.error: "viewyBackend=native selected, but native backends are not implemented yet".}
else:
  {.error: "unsupported -d:viewyBackend value; expected 'native' or 'lite'".}
