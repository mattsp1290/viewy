## Runtime AppIndicator loader for the native Linux backend.
##
## libayatana-appindicator3 is intentionally a soft dependency: the backend
## dlopens it when present and omits capTray when it is not available.

import std/[dynlib, locks, os]

import ./gtk_ffi

type
  AppIndicator* {.incompleteStruct.} = object

  AppIndicatorApi* = ref object
    lib: LibHandle
    newIndicator: proc(id, iconName: cstring; category: cint): ptr AppIndicator
        {.cdecl.}
    newIndicatorWithPath: proc(id, iconName: cstring; category: cint;
        iconThemePath: cstring): ptr AppIndicator {.cdecl.}
    setIconFull: proc(indicator: ptr AppIndicator; iconName,
        iconDesc: cstring) {.cdecl.}
    setIconThemePath: proc(indicator: ptr AppIndicator;
        iconThemePath: cstring) {.cdecl.}
    setMenu: proc(indicator: ptr AppIndicator; menu: ptr GtkMenu) {.cdecl.}
    setStatus: proc(indicator: ptr AppIndicator; status: cint) {.cdecl.}
    setTitle: proc(indicator: ptr AppIndicator; title: cstring) {.cdecl.}

const
  appIndicatorCategoryApplicationStatus * = cint(0)
  appIndicatorStatusPassive* = cint(0)
  appIndicatorStatusActive* = cint(1)

var cachedApi {.global.}: AppIndicatorApi
var attemptedLoad {.global.}: bool
var loaderLock {.global.}: Lock

initLock(loaderLock)

proc loadSymbol[T](lib: LibHandle; name: string): T =
  cast[T](symAddr(lib, name))

proc tryLoad(name: string): AppIndicatorApi =
  let lib = loadLib(name)
  if lib == nil:
    return nil

  let api = AppIndicatorApi(
    lib: lib,
    newIndicator: loadSymbol[typeof(result.newIndicator)](lib,
        "app_indicator_new"),
    newIndicatorWithPath: loadSymbol[typeof(result.newIndicatorWithPath)](lib,
        "app_indicator_new_with_path"),
    setIconFull: loadSymbol[typeof(result.setIconFull)](lib,
        "app_indicator_set_icon_full"),
    setIconThemePath: loadSymbol[typeof(result.setIconThemePath)](lib,
        "app_indicator_set_icon_theme_path"),
    setMenu: loadSymbol[typeof(result.setMenu)](lib, "app_indicator_set_menu"),
    setStatus: loadSymbol[typeof(result.setStatus)](lib,
        "app_indicator_set_status"),
    setTitle: loadSymbol[typeof(result.setTitle)](lib,
        "app_indicator_set_title"),
  )
  if api.newIndicator == nil or api.setIconFull == nil or
      api.setMenu == nil or api.setStatus == nil or api.setTitle == nil:
    unloadLib(lib)
    return nil
  api

proc loadAppIndicator*(): AppIndicatorApi {.gcsafe.} =
  {.cast(gcsafe).}:
    acquire(loaderLock)
    try:
      if attemptedLoad:
        return cachedApi
      attemptedLoad = true
      for name in [
        "libayatana-appindicator3.so.1",
        "libayatana-appindicator3.so",
        "libappindicator3.so.1",
        "libappindicator3.so",
      ]:
        cachedApi = tryLoad(name)
        if cachedApi != nil:
          return cachedApi
      cachedApi
    finally:
      release(loaderLock)

proc appIndicatorAvailable*(): bool {.gcsafe.} =
  loadAppIndicator() != nil

proc iconNameAndPath(iconPath, fallbackPath: string): tuple[name,
    themePath: string] =
  let path = if iconPath.len > 0: iconPath else: fallbackPath
  if path.len == 0:
    return ("viewy", "")
  let split = splitFile(path)
  if split.dir.len > 0:
    let name = if split.name.len > 0: split.name else: extractFilename(path)
    return (name, split.dir)
  (path, "")

proc newIndicator*(api: AppIndicatorApi; id, iconPath,
    fallbackPath: string): ptr AppIndicator =
  let icon = iconNameAndPath(iconPath, fallbackPath)
  if api.newIndicatorWithPath != nil and icon.themePath.len > 0:
    return api.newIndicatorWithPath(id.cstring, icon.name.cstring,
        appIndicatorCategoryApplicationStatus, icon.themePath.cstring)
  api.newIndicator(id.cstring, icon.name.cstring,
      appIndicatorCategoryApplicationStatus)

proc setIcon*(api: AppIndicatorApi; indicator: ptr AppIndicator; iconPath,
    fallbackPath, description: string) =
  if indicator == nil:
    return
  let icon = iconNameAndPath(iconPath, fallbackPath)
  if api.setIconThemePath != nil and icon.themePath.len > 0:
    api.setIconThemePath(indicator, icon.themePath.cstring)
  api.setIconFull(indicator, icon.name.cstring, description.cstring)

proc setMenu*(api: AppIndicatorApi; indicator: ptr AppIndicator;
    menu: ptr GtkWidget) =
  api.setMenu(indicator, cast[ptr GtkMenu](menu))

proc setStatus*(api: AppIndicatorApi; indicator: ptr AppIndicator;
    active: bool) {.gcsafe.} =
  {.cast(gcsafe).}:
    api.setStatus(indicator, if active: appIndicatorStatusActive else:
        appIndicatorStatusPassive)

proc setTitle*(api: AppIndicatorApi; indicator: ptr AppIndicator;
    title: string) =
  api.setTitle(indicator, title.cstring)
