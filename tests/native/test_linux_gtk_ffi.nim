when not defined(linux):
  echo "skipped linux gtk ffi: non-linux host"
else:
  import viewy/backend/native/linux/gtk_ffi

  doAssert ord(gtkWindowToplevel) == 0
  doAssert ord(gtkOrientationVertical) == 1
  doAssert gFalse == 0
  doAssert gTrue == 1

  echo "ok: linux gtk ffi declarations"
