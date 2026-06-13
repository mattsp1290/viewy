## Hand-written GTK3 FFI surface for the native Linux backend.
##
## Keep this file to declarations only. The backend owns GTK object lifetime and
## thread handoff; this module only exposes the C ABI symbols it needs.

{.passC: "-DVIEWY_APPINDICATOR_HEADER='\"libayatana-appindicator/app-indicator.h\"'".}

when defined(linux) and not defined(nimcheck):
  import std/strutils

  proc pkgConfig(package: string): tuple[ok: bool; cflags,
      libs: string] {.compileTime.} =
    let cflags = gorge("pkg-config --cflags " & package).strip()
    if cflags.len == 0:
      return (false, "", "")
    let libs = gorge("pkg-config --libs " & package).strip()
    if libs.len == 0:
      return (false, "", "")
    (true, cflags, libs)

  const gtk3 = pkgConfig("gtk+-3.0")
  when not gtk3.ok:
    {.error: "install libgtk-3-dev and pkg-config for viewy native Linux backend".}

  const appIndicator = block:
    let ayatana = pkgConfig("ayatana-appindicator3-0.1")
    if ayatana.ok:
      ayatana
    else:
      pkgConfig("appindicator3-0.1")
  const appIndicatorHeader = block:
    let ayatana = pkgConfig("ayatana-appindicator3-0.1")
    if ayatana.ok:
      "libayatana-appindicator/app-indicator.h"
    else:
      "libappindicator/app-indicator.h"

  {.passC: gtk3.cflags.}
  {.passL: gtk3.libs.}
  when appIndicator.ok:
    {.passC: appIndicator.cflags & " -DVIEWY_HAS_APPINDICATOR=1" &
        " -DVIEWY_APPINDICATOR_HEADER='\"" & appIndicatorHeader & "\"'".}
    {.passL: appIndicator.libs.}

type
  GConnectFlags* {.size: sizeof(cint).} = enum
    gConnectDefault = 0
    gConnectAfter = 1
    gConnectSwapped = 2
  GBoolean* = cint
  GChar* {.importc: "gchar", header: "glib.h".} = char
  GConstPointer* {.importc: "gconstpointer", header: "glib.h".} = pointer
  GDestroyNotify* = proc(data: pointer) {.cdecl, gcsafe.}
  GError* {.importc: "GError", header: "glib.h", incompleteStruct.} = object
  GObject* {.importc: "GObject", header: "glib-object.h",
      incompleteStruct.} = object
  GPointer* {.importc: "gpointer", header: "glib.h".} = pointer
  GQuark* {.importc: "GQuark", header: "glib.h".} = cuint
  GSourceFunc* = proc(data: pointer): GBoolean {.cdecl, gcsafe.}
  GSList* {.importc: "GSList", header: "glib.h", incompleteStruct.} = object
  GType* {.importc: "GType", header: "glib-object.h".} = culong
  GValue* {.importc: "GValue", header: "glib-object.h",
      incompleteStruct.} = object
  GVariant* {.importc: "GVariant", header: "glib.h", incompleteStruct.} = object
  GdkEvent* {.importc: "GdkEvent", header: "gdk/gdk.h",
      incompleteStruct.} = object
  GdkEventConfigure* {.importc: "GdkEventConfigure", header: "gdk/gdk.h",
      bycopy.} = object
    eventType* {.importc: "type".}: cint
    window* {.importc: "window".}: pointer
    sendEvent* {.importc: "send_event".}: int8
    x*: cint
    y*: cint
    width*: cint
    height*: cint
  GtkAccelGroup* {.importc: "GtkAccelGroup", header: "gtk/gtk.h",
      incompleteStruct.} = object
  GtkAccelFlags* {.size: sizeof(cint).} = enum
    gtkAccelVisible = 1
    gtkAccelLocked = 2
    gtkAccelMask = 7
  GtkAccelKey* {.importc: "GtkAccelKey", header: "gtk/gtk.h",
      incompleteStruct.} = object
  GtkApplicationIndicator* {.importc: "AppIndicator",
      header: "VIEWY_APPINDICATOR_HEADER",
      incompleteStruct.} = object
  GtkApplication* {.importc: "GtkApplication", header: "gtk/gtk.h",
      incompleteStruct.} = object
  GtkApplicationWindow* {.importc: "GtkApplicationWindow", header: "gtk/gtk.h",
      incompleteStruct.} = object
  GtkBox* {.importc: "GtkBox", header: "gtk/gtk.h", incompleteStruct.} = object
  GtkCheckMenuItem* {.importc: "GtkCheckMenuItem", header: "gtk/gtk.h",
      incompleteStruct.} = object
  GtkContainer* {.importc: "GtkContainer", header: "gtk/gtk.h",
      incompleteStruct.} = object
  GtkMenu* {.importc: "GtkMenu", header: "gtk/gtk.h",
      incompleteStruct.} = object
  GtkMenuBar* {.importc: "GtkMenuBar", header: "gtk/gtk.h",
      incompleteStruct.} = object
  GtkMenuItem* {.importc: "GtkMenuItem", header: "gtk/gtk.h",
      incompleteStruct.} = object
  GtkOrientation* {.size: sizeof(cint).} = enum
    gtkOrientationHorizontal = 0
    gtkOrientationVertical = 1
  GtkRadioMenuItem* {.importc: "GtkRadioMenuItem", header: "gtk/gtk.h",
      incompleteStruct.} = object
  GtkSeparatorMenuItem* {.importc: "GtkSeparatorMenuItem", header: "gtk/gtk.h",
      incompleteStruct.} = object
  GtkStatusIcon* {.importc: "GtkStatusIcon", header: "gtk/gtk.h",
      incompleteStruct.} = object
  GtkWidget* {.importc: "GtkWidget", header: "gtk/gtk.h",
      incompleteStruct.} = object
  GtkWindow* {.importc: "GtkWindow", header: "gtk/gtk.h",
      incompleteStruct.} = object
  GtkWindowPosition* {.size: sizeof(cint).} = enum
    gtkWinPosNone = 0
    gtkWinPosCenter = 1
    gtkWinPosMouse = 2
    gtkWinPosCenterAlways = 3
    gtkWinPosCenterOnParent = 4
  GtkWindowType* {.size: sizeof(cint).} = enum
    gtkWindowToplevel = 0
    gtkWindowPopup = 1
  AppIndicatorCategory* {.size: sizeof(cint).} = enum
    appIndicatorCategoryApplicationStatus = 0
    appIndicatorCategoryCommunications = 1
    appIndicatorCategorySystemServices = 2
    appIndicatorCategoryHardware = 3
    appIndicatorCategoryOther = 4
  AppIndicatorStatus* {.size: sizeof(cint).} = enum
    appIndicatorStatusPassive = 0
    appIndicatorStatusActive = 1
    appIndicatorStatusAttention = 2
  GtkDeleteEventCallback* = proc(widget: ptr GtkWidget; event: ptr GdkEvent;
      data: pointer): GBoolean {.cdecl, gcsafe.}
  GtkFocusEventCallback* = proc(widget: ptr GtkWidget; event: ptr GdkEvent;
      data: pointer): GBoolean {.cdecl, gcsafe.}
  GtkConfigureEventCallback* = proc(widget: ptr GtkWidget;
      event: ptr GdkEventConfigure; data: pointer): GBoolean {.cdecl, gcsafe.}
  GtkMenuItemCallback* = proc(menuItem: ptr GtkMenuItem; data: pointer)
      {.cdecl, gcsafe.}
  GtkStatusIconActivateCallback* = proc(statusIcon: ptr GtkStatusIcon;
      data: pointer) {.cdecl, gcsafe.}
  GtkStatusIconPopupMenuCallback* = proc(statusIcon: ptr GtkStatusIcon;
      button, activateTime: cuint; data: pointer) {.cdecl, gcsafe.}

const
  gFalse* = GBoolean(0)
  gTrue* = GBoolean(1)

proc gObjectRef*(obj: pointer): pointer
  {.importc: "g_object_ref", header: "glib-object.h", cdecl.}

proc gObjectUnref*(obj: pointer)
  {.importc: "g_object_unref", header: "glib-object.h", cdecl.}

proc gSignalConnectData*(instance: pointer; detailedSignal: cstring;
    callback: pointer; data: pointer; destroyData: GDestroyNotify;
    connectFlags: GConnectFlags): culong
  {.importc: "g_signal_connect_data", header: "glib-object.h", cdecl.}

proc gIdleAdd*(function: GSourceFunc; data: pointer): cuint
  {.importc: "g_idle_add", header: "glib.h", cdecl.}

proc gTimeoutAdd*(interval: cuint; function: GSourceFunc; data: pointer): cuint
  {.importc: "g_timeout_add", header: "glib.h", cdecl.}

proc gtkAccelGroupNew*(): ptr GtkAccelGroup
  {.importc: "gtk_accel_group_new", header: "gtk/gtk.h", cdecl.}

proc gtkAcceleratorParse*(accelerator: cstring; acceleratorKey: ptr cuint;
    acceleratorMods: ptr cint)
  {.importc: "gtk_accelerator_parse", header: "gtk/gtk.h", cdecl.}

proc gtkBoxNew*(orientation: GtkOrientation; spacing: cint): ptr GtkWidget
  {.importc: "gtk_box_new", header: "gtk/gtk.h", cdecl.}

proc gtkBoxPackStart*(box: ptr GtkBox; child: ptr GtkWidget; expand,
    fill: GBoolean; padding: cuint)
  {.importc: "gtk_box_pack_start", header: "gtk/gtk.h", cdecl.}

proc gtkCheckMenuItemGetActive*(checkMenuItem: ptr GtkCheckMenuItem): GBoolean
  {.importc: "gtk_check_menu_item_get_active", header: "gtk/gtk.h", cdecl.}

proc gtkCheckMenuItemNewWithLabel*(label: cstring): ptr GtkWidget
  {.importc: "gtk_check_menu_item_new_with_label", header: "gtk/gtk.h", cdecl.}

proc gtkCheckMenuItemSetActive*(checkMenuItem: ptr GtkCheckMenuItem;
    isActive: GBoolean)
  {.importc: "gtk_check_menu_item_set_active", header: "gtk/gtk.h", cdecl.}

proc gtkContainerAdd*(container: ptr GtkContainer; widget: ptr GtkWidget)
  {.importc: "gtk_container_add", header: "gtk/gtk.h", cdecl.}

proc gtkContainerRemove*(container: ptr GtkContainer; widget: ptr GtkWidget)
  {.importc: "gtk_container_remove", header: "gtk/gtk.h", cdecl.}

proc gtkInit*(argc: ptr cint; argv: ptr cstringArray)
  {.importc: "gtk_init", header: "gtk/gtk.h", cdecl.}

proc gtkInitCheck*(argc: ptr cint; argv: ptr cstringArray): GBoolean
  {.importc: "gtk_init_check", header: "gtk/gtk.h", cdecl.}

proc gtkMain*()
  {.importc: "gtk_main", header: "gtk/gtk.h", cdecl.}

proc gtkMainIterationDo*(blocking: GBoolean): GBoolean
  {.importc: "gtk_main_iteration_do", header: "gtk/gtk.h", cdecl.}

proc gtkMainLevel*(): cuint
  {.importc: "gtk_main_level", header: "gtk/gtk.h", cdecl.}

proc gtkMainQuit*()
  {.importc: "gtk_main_quit", header: "gtk/gtk.h", cdecl.}

proc gtkMenuBarNew*(): ptr GtkWidget
  {.importc: "gtk_menu_bar_new", header: "gtk/gtk.h", cdecl.}

proc gtkMenuItemNewWithLabel*(label: cstring): ptr GtkWidget
  {.importc: "gtk_menu_item_new_with_label", header: "gtk/gtk.h", cdecl.}

proc gtkMenuItemSetSubmenu*(menuItem: ptr GtkMenuItem; submenu: ptr GtkWidget)
  {.importc: "gtk_menu_item_set_submenu", header: "gtk/gtk.h", cdecl.}

proc gtkMenuNew*(): ptr GtkWidget
  {.importc: "gtk_menu_new", header: "gtk/gtk.h", cdecl.}

proc gtkMenuPopupAtPointer*(menu: ptr GtkMenu; triggerEvent: pointer)
  {.importc: "gtk_menu_popup_at_pointer", header: "gtk/gtk.h", cdecl.}

proc gtkMenuPopup*(menu: ptr GtkMenu; parentMenuShell: ptr GtkWidget;
    parentMenuItem: ptr GtkWidget; menuPositionFunc: pointer; data: pointer;
    button, activateTime: cuint)
  {.importc: "gtk_menu_popup", header: "gtk/gtk.h", cdecl.}

proc gtkMenuShellAppend*(menuShell: pointer; child: ptr GtkWidget)
  {.importc: "gtk_menu_shell_append", header: "gtk/gtk.h", cdecl.}

proc gtkRadioMenuItemGetGroup*(radioMenuItem: ptr GtkRadioMenuItem): ptr GSList
  {.importc: "gtk_radio_menu_item_get_group", header: "gtk/gtk.h", cdecl.}

proc gtkRadioMenuItemNewWithLabel*(group: pointer;
    label: cstring): ptr GtkWidget
  {.importc: "gtk_radio_menu_item_new_with_label", header: "gtk/gtk.h", cdecl.}

proc gtkRadioMenuItemNewWithLabelFromWidget*(
    group: ptr GtkRadioMenuItem; label: cstring): ptr GtkWidget
  {.importc: "gtk_radio_menu_item_new_with_label_from_widget",
      header: "gtk/gtk.h", cdecl.}

proc gtkSeparatorMenuItemNew*(): ptr GtkWidget
  {.importc: "gtk_separator_menu_item_new", header: "gtk/gtk.h", cdecl.}

proc gtkStatusIconNew*(): ptr GtkStatusIcon
  {.importc: "gtk_status_icon_new", header: "gtk/gtk.h", cdecl.}

proc gtkStatusIconSetFromFile*(statusIcon: ptr GtkStatusIcon; filename: cstring)
  {.importc: "gtk_status_icon_set_from_file", header: "gtk/gtk.h", cdecl.}

proc gtkStatusIconSetTooltipText*(statusIcon: ptr GtkStatusIcon; text: cstring)
  {.importc: "gtk_status_icon_set_tooltip_text", header: "gtk/gtk.h", cdecl.}

proc gtkStatusIconSetVisible*(statusIcon: ptr GtkStatusIcon; visible: GBoolean)
  {.importc: "gtk_status_icon_set_visible", header: "gtk/gtk.h", cdecl.}

proc gtkStatusIconPositionMenu*(menu: ptr GtkMenu; x, y: ptr cint;
    pushIn: ptr GBoolean; userData: pointer)
  {.importc: "gtk_status_icon_position_menu", header: "gtk/gtk.h", cdecl.}

proc gtkWidgetAddAccelerator*(widget: ptr GtkWidget; accelSignal: cstring;
    accelGroup: ptr GtkAccelGroup; accelKey: cuint; accelMods: cint;
    accelFlags: GtkAccelFlags)
  {.importc: "gtk_widget_add_accelerator", header: "gtk/gtk.h", cdecl.}

proc gtkWidgetDestroy*(widget: ptr GtkWidget)
  {.importc: "gtk_widget_destroy", header: "gtk/gtk.h", cdecl.}

proc gtkWidgetGetToplevel*(widget: ptr GtkWidget): ptr GtkWidget
  {.importc: "gtk_widget_get_toplevel", header: "gtk/gtk.h", cdecl.}

proc gtkWidgetGrabFocus*(widget: ptr GtkWidget)
  {.importc: "gtk_widget_grab_focus", header: "gtk/gtk.h", cdecl.}

proc gtkWidgetSetSensitive*(widget: ptr GtkWidget; sensitive: GBoolean)
  {.importc: "gtk_widget_set_sensitive", header: "gtk/gtk.h", cdecl.}

proc gtkWidgetShow*(widget: ptr GtkWidget)
  {.importc: "gtk_widget_show", header: "gtk/gtk.h", cdecl.}

proc gtkWidgetShowAll*(widget: ptr GtkWidget)
  {.importc: "gtk_widget_show_all", header: "gtk/gtk.h", cdecl.}

proc gtkWindowAddAccelGroup*(window: ptr GtkWindow;
    accelGroup: ptr GtkAccelGroup)
  {.importc: "gtk_window_add_accel_group", header: "gtk/gtk.h", cdecl.}

proc gtkWindowNew*(windowType: GtkWindowType): ptr GtkWidget
  {.importc: "gtk_window_new", header: "gtk/gtk.h", cdecl.}

proc gtkWindowPresent*(window: ptr GtkWindow)
  {.importc: "gtk_window_present", header: "gtk/gtk.h", cdecl.}

proc gtkWindowResize*(window: ptr GtkWindow; width, height: cint)
  {.importc: "gtk_window_resize", header: "gtk/gtk.h", cdecl.}

proc gtkWindowSetDefaultSize*(window: ptr GtkWindow; width, height: cint)
  {.importc: "gtk_window_set_default_size", header: "gtk/gtk.h", cdecl.}

proc gtkWindowSetPosition*(window: ptr GtkWindow; position: GtkWindowPosition)
  {.importc: "gtk_window_set_position", header: "gtk/gtk.h", cdecl.}

proc gtkWindowSetResizable*(window: ptr GtkWindow; resizable: GBoolean)
  {.importc: "gtk_window_set_resizable", header: "gtk/gtk.h", cdecl.}

proc gtkWindowSetTitle*(window: ptr GtkWindow; title: cstring)
  {.importc: "gtk_window_set_title", header: "gtk/gtk.h", cdecl.}

proc gtkWindowGetSize*(window: ptr GtkWindow; width, height: ptr cint)
  {.importc: "gtk_window_get_size", header: "gtk/gtk.h", cdecl.}

when defined(VIEWY_HAS_APPINDICATOR) or defined(nimcheck):
  proc appIndicatorNew*(id, iconName: cstring;
      category: AppIndicatorCategory): ptr GtkApplicationIndicator
    {.importc: "app_indicator_new",
        header: "VIEWY_APPINDICATOR_HEADER", cdecl.}

  proc appIndicatorSetIconFull*(self: ptr GtkApplicationIndicator;
      iconName, iconDesc: cstring)
    {.importc: "app_indicator_set_icon_full",
        header: "VIEWY_APPINDICATOR_HEADER", cdecl.}

  proc appIndicatorSetMenu*(self: ptr GtkApplicationIndicator;
      menu: ptr GtkMenu)
    {.importc: "app_indicator_set_menu",
        header: "VIEWY_APPINDICATOR_HEADER", cdecl.}

  proc appIndicatorSetStatus*(self: ptr GtkApplicationIndicator;
      status: AppIndicatorStatus)
    {.importc: "app_indicator_set_status",
        header: "VIEWY_APPINDICATOR_HEADER", cdecl.}

  proc appIndicatorSetTitle*(self: ptr GtkApplicationIndicator; title: cstring)
    {.importc: "app_indicator_set_title",
        header: "VIEWY_APPINDICATOR_HEADER", cdecl.}
