## Hand-written GTK3 FFI surface for the native Linux backend.
##
## Keep this file to declarations only. The backend owns GTK object lifetime and
## thread handoff; this module only exposes the C ABI symbols it needs.

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

  {.passC: gtk3.cflags.}
  {.passL: gtk3.libs.}

type
  GBoolean* = cint
  GChar* {.importc: "gchar", header: "glib.h".} = char
  GConstPointer* {.importc: "gconstpointer", header: "glib.h".} = pointer
  GDestroyNotify* = proc(data: pointer) {.cdecl, gcsafe.}
  GError* {.importc: "GError", header: "glib.h", incompleteStruct.} = object
  GObject* {.importc: "GObject", header: "glib-object.h",
      incompleteStruct.} = object
  GPointer* {.importc: "gpointer", header: "glib.h".} = pointer
  GQuark* {.importc: "GQuark", header: "glib.h".} = cuint
  GSignalCallback* = proc(instance: pointer; data: pointer) {.cdecl, gcsafe.}
  GSourceFunc* = proc(data: pointer): GBoolean {.cdecl, gcsafe.}
  GType* {.importc: "GType", header: "glib-object.h".} = culong
  GValue* {.importc: "GValue", header: "glib-object.h",
      incompleteStruct.} = object
  GVariant* {.importc: "GVariant", header: "glib.h", incompleteStruct.} = object
  GtkAccelGroup* {.importc: "GtkAccelGroup", header: "gtk/gtk.h",
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

const
  gFalse* = GBoolean(0)
  gTrue* = GBoolean(1)

proc gObjectRef*(obj: pointer): pointer
  {.importc: "g_object_ref", header: "glib-object.h", cdecl.}

proc gObjectUnref*(obj: pointer)
  {.importc: "g_object_unref", header: "glib-object.h", cdecl.}

proc gSignalConnectData*(instance: pointer; detailedSignal: cstring;
    callback: pointer; data: pointer; destroyData: GDestroyNotify;
    connectFlags: cint): culong
  {.importc: "g_signal_connect_data", header: "glib-object.h", cdecl.}

proc gTimeoutAdd*(interval: cuint; function: GSourceFunc; data: pointer): cuint
  {.importc: "g_timeout_add", header: "glib.h", cdecl.}

proc gtkAccelGroupNew*(): ptr GtkAccelGroup
  {.importc: "gtk_accel_group_new", header: "gtk/gtk.h", cdecl.}

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

proc gtkMenuShellAppend*(menuShell: pointer; child: ptr GtkWidget)
  {.importc: "gtk_menu_shell_append", header: "gtk/gtk.h", cdecl.}

proc gtkRadioMenuItemNewWithLabel*(group: pointer;
    label: cstring): ptr GtkWidget
  {.importc: "gtk_radio_menu_item_new_with_label", header: "gtk/gtk.h", cdecl.}

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
