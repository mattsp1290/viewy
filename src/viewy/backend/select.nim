## Compile-time backend selection.

import viewy/backend/api

when selectedBackend == "lite":
  import viewy/backend/lite/backend
  export backend.newBackend
elif selectedBackend == "native":
  when defined(linux):
    when defined(viewyGtk4):
      {.error: "-d:viewyGtk4 is only supported with -d:viewyBackend=lite; native Linux uses GTK3 + webkit2gtk-4.1".}
    import viewy/backend/native/linux/backend
    export backend.newBackend
  elif defined(macosx):
    import viewy/backend/native/darwin/backend
    export backend.newBackend
  elif defined(windows):
    import viewy/backend/native/windows/backend
    export backend.newBackend
  else:
    template newBackend*(): Backend =
      {.error: "viewyBackend=native currently requires Linux or macOS".}
else:
  {.error: "unsupported -d:viewyBackend value; expected 'native' or 'lite'".}
