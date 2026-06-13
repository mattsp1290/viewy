## Compile-time backend selection.

import viewy/backend/api

when selectedBackend == "lite":
  import viewy/backend/lite/backend
  export backend.newBackend
elif selectedBackend == "native":
  when defined(linux):
    import viewy/backend/native/linux/backend
    export backend.newBackend
  else:
    template newBackend*(): Backend =
      {.error: "viewyBackend=native currently requires Linux".}
else:
  {.error: "unsupported -d:viewyBackend value; expected 'native' or 'lite'".}
