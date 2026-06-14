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
  doAssert wmDpiChanged == 0x02E0'u32
  doAssert wmGetDpiScaledSize == 0x02E4'u32
  doAssert wmApp == 0x8000'u32
  doAssert (wsOverlappedWindow and wsCaption) == wsCaption
  doAssert wsExControlParent == 0x00010000'u32
  doAssert (fvVirtKey or fControl or fShift) == Byte(0x0D)
  doAssert vkF12 == 0x7B'u16
  doAssert dpiAwarenessContextPerMonitorAwareV2() == cast[DpiAwarenessContext](-4)
  doAssert hwndMessage() == cast[Hwnd](-3)

  when defined(nimcheck):
    var
      rect = Rect(left: 0, top: 0, right: 800, bottom: 600)
      msg: Msg
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
    discard registerClassExW(addr wc)
    let hwnd = createWindowExW(0, wc.lpszClassName, newWideCString("Viewy"),
      wsOverlappedWindow or wsVisible, cwUseDefault, cwUseDefault, 800, 600,
      nil, nil, wc.hInstance, nil)
    discard showWindow(hwnd, swShow)
    discard updateWindow(hwnd)
    discard setWindowTextW(hwnd, newWideCString("Updated"))
    discard moveWindow(hwnd, 0, 0, 800, 600, winTrue)
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
