when not defined(windows):
  echo "skipped windows win32 ffi: non-Windows host"
else:
  import viewy/backend/native/windows/win32

  proc windowProc(hwnd: Hwnd; msg: Uint; wParam: Wparam;
      lParam: Lparam): Lresult {.stdcall, gcsafe.} =
    discard hwnd
    discard wParam
    discard lParam
    if msg == wmDestroy:
      postQuitMessage(0)
      return 0
    defWindowProcW(hwnd, msg, wParam, lParam)

  doAssert winFalse == 0
  doAssert winTrue == 1
  doAssert wmCreate == 0x0001'u32
  doAssert wmNcCreate == 0x0081'u32
  doAssert wmLButtonUp == 0x0202'u32
  doAssert wmRButtonUp == 0x0205'u32
  doAssert wmDpiChanged == 0x02E0'u32
  doAssert wmGetDpiScaledSize == 0x02E4'u32
  doAssert wmApp == 0x8000'u32
  doAssert swpNoMove == 0x0002'u32
  doAssert (wsOverlappedWindow and wsCaption) == wsCaption
  doAssert wsExControlParent == 0x00010000'u32
  doAssert (fvVirtKey or fControl or fShift) == Byte(0x0D)
  doAssert vkF12 == 0x7B'u16
  doAssert dpiAwarenessContextPerMonitorAwareV2() == cast[DpiAwarenessContext](-4)
  doAssert hwndMessage() == cast[Hwnd](-3)
  doAssert idiApplication() == cast[Lpcwstr](idiApplicationValue)
  doAssert (nifMessage or nifIcon or nifTip) == 0x00000007'u32
  doAssert nimAdd == 0'u32
  doAssert nimModify == 1'u32
  doAssert nimDelete == 2'u32
  doAssert nimSetVersion == 4'u32
  doAssert notifyIconVersion4 == 4'u32
  doAssert mfSeparator == 0x00000800'u32
  doAssert mfPopup == 0x00000010'u32

  when defined(nimcheck):
    var
      rect = Rect(left: 0, top: 0, right: 800, bottom: 600)
      msg: Msg
      point: Point
      nid = NotifyIconDataW(
        cbSize: Dword(sizeof(NotifyIconDataW)),
        uFlags: nifMessage or nifIcon or nifTip,
        uCallbackMessage: wmApp,
        uVersion: notifyIconVersion4,
      )
      accel = Accel(fVirt: fvVirtKey or fControl, key: Word('Q'.ord),
        cmd: Word(100))
      wc = WndClassExW(
        cbSize: Uint(sizeof(WndClassExW)),
        style: csHRedraw or csVRedraw,
        lpfnWndProc: windowProc,
        hInstance: getModuleHandleW(nil),
        hCursor: loadCursorW(nil, idcArrow()),
        lpszClassName: newWideCString("ViewyWindow"),
      )
    let appIcon = loadIconW(nil, idiApplication())
    discard registerWindowMessageW(newWideCString("TaskbarCreated"))
    discard loadImageW(nil, newWideCString("icon.ico"), imageIcon, 0, 0,
      lrLoadFromFile)
    discard registerClassExW(addr wc)
    let hwnd = createWindowExW(0, wc.lpszClassName, newWideCString("Viewy"),
      wsOverlappedWindow or wsVisible, cwUseDefault, cwUseDefault, 800, 600,
      nil, nil, wc.hInstance, nil)
    nid.hWnd = hwnd
    nid.uID = 1
    nid.hIcon = appIcon
    discard shellNotifyIconW(nimAdd, addr nid)
    discard shellNotifyIconW(nimModify, addr nid)
    discard shellNotifyIconW(nimSetVersion, addr nid)
    discard shellNotifyIconW(nimDelete, addr nid)
    let menu = createPopupMenu()
    let submenu = createPopupMenu()
    discard appendMenuW(menu, mfString, 1, newWideCString("Open"))
    discard appendMenuW(menu, mfSeparator, 0, nil)
    discard appendMenuW(menu, mfPopup, cast[UintPtr](submenu),
      newWideCString("More"))
    discard getCursorPos(addr point)
    discard setForegroundWindow(hwnd)
    discard trackPopupMenu(menu, tpmRightButton, point.x, point.y, 0, hwnd, nil)
    discard destroyMenu(menu)
    discard showWindow(hwnd, swShow)
    discard updateWindow(hwnd)
    discard setWindowTextW(hwnd, newWideCString("Updated"))
    discard moveWindow(hwnd, 0, 0, 800, 600, winTrue)
    discard setWindowPos(hwnd, nil, 0, 0, 800, 600, swpNoMove or swpNoZOrder)
    discard getClientRect(hwnd, addr rect)
    discard adjustWindowRectEx(addr rect, wsOverlappedWindow, winFalse, 0)
    discard adjustWindowRectExForDpi(addr rect, wsOverlappedWindow, winFalse, 0,
      96)
    discard getDpiForWindow(hwnd)
    discard enableNonClientDpiScaling(hwnd)
    discard setProcessDpiAwarenessContext(dpiAwarenessContextPerMonitorAwareV2())
    discard setWindowLongPtrW(hwnd, gwlUserData, 0)
    discard setWindowLongPtrW(hwnd, gwlpWndProc, cast[LongPtr](windowProc))
    discard setWindowLongPtrW(hwnd, gwlpUserData, 0)
    discard getWindowLongPtrW(hwnd, gwlUserData)
    discard getWindowLongPtrW(hwnd, gwlpUserData)
    let haccel = createAcceleratorTableW(addr accel, 1)
    discard translateAcceleratorW(hwnd, haccel, addr msg)
    discard destroyAcceleratorTable(haccel)
    discard peekMessageW(addr msg, nil, 0, 0, pmRemove)
    discard getMessageW(addr msg, nil, 0, 0)
    discard translateMessage(addr msg)
    discard dispatchMessageW(addr msg)
    discard postMessageW(hwnd, wmClose, 0, 0)
    discard sendMessageW(hwnd, wmClose, 0, 0)
    discard createWindowExW(0, wc.lpszClassName, nil, 0, 0, 0, 0, 0,
      hwndMessage(), nil, wc.hInstance, nil)
    discard destroyWindow(hwnd)

  echo "ok: windows win32 ffi declarations"
