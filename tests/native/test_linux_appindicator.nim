when not defined(linux):
  echo "skipped linux appindicator: non-linux host"
else:
  import viewy/backend/api
  import viewy/backend/native/linux/appindicator
  import viewy/backend/native/linux/backend
  import viewy/backend/native/linux/gtk_ffi

  doAssert appIndicatorStatusPassive == 0
  doAssert appIndicatorStatusActive == 1
  doAssert selectedBackendCaps == {capScheme, capMenu, capContextMenu, capTray,
      capWindowVisibility}

  let nativeBackend = newBackend()
  if appIndicatorAvailable():
    doAssert capTray in nativeBackend.caps
    doAssert nativeBackend.trayCreateImpl != nil
    doAssert nativeBackend.trayUpdateImpl != nil
    doAssert nativeBackend.trayDestroyImpl != nil
  else:
    doAssert capTray notin nativeBackend.caps
    doAssert nativeBackend.trayCreateImpl == nil
    doAssert nativeBackend.trayUpdateImpl == nil
    doAssert nativeBackend.trayDestroyImpl == nil

  when defined(nimcheck):
    let indicatorApi = loadAppIndicator()
    if indicatorApi != nil:
      let indicator = indicatorApi.newIndicator("viewy", "viewy", "")
      let menu = gtkMenuNew()
      indicatorApi.setMenu(indicator, menu)
      indicatorApi.setIcon(indicator, "viewy", "", "Viewy")
      indicatorApi.setTitle(indicator, "Viewy")
      indicatorApi.setStatus(indicator, true)

  echo "ok: linux appindicator soft dependency"
