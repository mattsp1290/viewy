when not defined(linux):
  echo "skipped linux gtk ffi: non-linux host"
else:
  import viewy/backend/native/linux/gtk_ffi

  proc deleteCb(widget: ptr GtkWidget; event: ptr GdkEvent;
      data: pointer): GBoolean {.cdecl, gcsafe.} =
    discard widget
    discard event
    discard data
    gFalse

  proc configureCb(widget: ptr GtkWidget; event: ptr GdkEventConfigure;
      data: pointer): GBoolean {.cdecl, gcsafe.} =
    discard widget
    discard event.width
    discard event.height
    discard data
    gFalse

  proc sourceCb(data: pointer): GBoolean {.cdecl, gcsafe.} =
    discard data
    gFalse

  doAssert ord(gtkWindowToplevel) == 0
  doAssert ord(gtkOrientationVertical) == 1
  doAssert gFalse == 0
  doAssert gTrue == 1

  proc assertAcceleratorParses(value: string) =
    var
      accelKey: cuint
      accelMods: cint
    gtkAcceleratorParse(value.cstring, addr accelKey, addr accelMods)
    doAssert accelKey != 0

  assertAcceleratorParses("<Control>N")
  assertAcceleratorParses("<Control>plus")
  assertAcceleratorParses("<Alt>F4")
  assertAcceleratorParses("<Control><Shift>slash")
  assertAcceleratorParses("<Super>Return")

  when false:
    var
      argc: cint
      argv: cstringArray
      accelKey: cuint
      accelMods: cint
      width: cint
      height: cint
      pushIn: GBoolean
    let
      windowWidget = gtkWindowNew(gtkWindowToplevel)
      window = cast[ptr GtkWindow](windowWidget)
      accelGroup = gtkAccelGroupNew()
      menu = cast[ptr GtkMenu](gtkMenuNew())
      menuItem = gtkMenuItemNewWithLabel("Quit")
      radio = cast[ptr GtkRadioMenuItem](gtkRadioMenuItemNewWithLabel(nil, "One"))
      statusIcon = gtkStatusIconNew()
    gtkInit(addr argc, addr argv)
    discard gtkInitCheck(addr argc, addr argv)
    gtkAcceleratorParse("Ctrl+Q", addr accelKey, addr accelMods)
    gtkWindowAddAccelGroup(window, accelGroup)
    gtkWindowRemoveAccelGroup(window, accelGroup)
    gtkBoxReorderChild(cast[ptr GtkBox](gtkBoxNew(gtkOrientationVertical, 0)),
      menuItem, 0)
    gtkWidgetAddAccelerator(menuItem, "activate", accelGroup, accelKey,
      accelMods, gtkAccelVisible)
    discard gSignalConnectData(windowWidget, "delete-event", cast[pointer](
        deleteCb),
      nil, nil, gConnectDefault)
    discard gSignalConnectData(windowWidget, "configure-event",
      cast[pointer](configureCb), nil, nil, gConnectDefault)
    gtkWindowGetSize(window, addr width, addr height)
    discard gtkRadioMenuItemGetGroup(radio)
    discard gtkRadioMenuItemNewWithLabelFromWidget(radio, "Two")
    gtkStatusIconPositionMenu(menu, addr width, addr height, addr pushIn,
      statusIcon)
    discard gTimeoutAdd(1, sourceCb, nil)
  echo "ok: linux gtk ffi declarations"
