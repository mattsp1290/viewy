## Hand-written Win32 FFI surface for the native Windows backend.
##
## Keep this file to declarations and constants only. Backend modules own
## window lifetime, message dispatch, DPI policy, and cross-thread handoff.

when defined(windows):
  when defined(vcc):
    {.passL: "user32.lib kernel32.lib shell32.lib".}
  else:
    {.passL: "-luser32 -lkernel32 -lshell32".}

type
  Bool* = cint
  Byte* = uint8
  Word* = uint16
  Atom* = Word
  Dword* = uint32
  Uint* = cuint
  Int* = cint
  Long* = int32
  LongPtr* = int
  UintPtr* = uint
  DwordPtr* = uint
  Wparam* = UintPtr
  Lparam* = LongPtr
  Lresult* = LongPtr
  Hinstance* = pointer
  Hicon* = pointer
  Hcursor* = pointer
  Hbrush* = pointer
  Hmenu* = pointer
  Hwnd* = pointer
  Haccel* = pointer
  DpiAwarenessContext* = pointer
  Lpcwstr* = WideCString
  Lpwstr* = WideCString

  WndProc* = proc(hwnd: Hwnd; msg: Uint; wParam: Wparam;
      lParam: Lparam): Lresult {.stdcall, gcsafe.}

when defined(windows) or defined(nimcheck):
  type
    Point* {.importc: "POINT", header: "windows.h", bycopy.} = object
      x*: Long
      y*: Long

    Size* {.importc: "SIZE", header: "windows.h", bycopy.} = object
      cx*: Long
      cy*: Long

    Rect* {.importc: "RECT", header: "windows.h", bycopy.} = object
      left*: Long
      top*: Long
      right*: Long
      bottom*: Long

    Msg* {.importc: "MSG", header: "windows.h", bycopy.} = object
      hwnd*: Hwnd
      message*: Uint
      wParam*: Wparam
      lParam*: Lparam
      time*: Dword
      pt*: Point

    WndClassExW* {.importc: "WNDCLASSEXW", header: "windows.h",
        bycopy.} = object
      cbSize*: Uint
      style*: Uint
      lpfnWndProc*: WndProc
      cbClsExtra*: Int
      cbWndExtra*: Int
      hInstance*: Hinstance
      hIcon*: Hicon
      hCursor*: Hcursor
      hbrBackground*: Hbrush
      lpszMenuName*: Lpcwstr
      lpszClassName*: Lpcwstr
      hIconSm*: Hicon

    CreateStructW* {.importc: "CREATESTRUCTW", header: "windows.h",
        bycopy.} = object
      lpCreateParams*: pointer
      hInstance*: Hinstance
      hMenu*: Hmenu
      hwndParent*: Hwnd
      cy*: Int
      cx*: Int
      y*: Int
      x*: Int
      style*: Long
      lpszName*: Lpcwstr
      lpszClass*: Lpcwstr
      dwExStyle*: Dword

    MinMaxInfo* {.importc: "MINMAXINFO", header: "windows.h",
        bycopy.} = object
      ptReserved*: Point
      ptMaxSize*: Point
      ptMaxPosition*: Point
      ptMinTrackSize*: Point
      ptMaxTrackSize*: Point

    Accel* {.importc: "ACCEL", header: "windows.h", bycopy.} = object
      fVirt*: Byte
      key*: Word
      cmd*: Word

    Guid* {.importc: "GUID", header: "windows.h", bycopy.} = object
      data1*: Dword
      data2*: Word
      data3*: Word
      data4*: array[8, Byte]

    NotifyIconDataW* {.importc: "NOTIFYICONDATAW", header: "shellapi.h",
        bycopy.} = object
      cbSize*: Dword
      hWnd*: Hwnd
      uID*: Uint
      uFlags*: Uint
      uCallbackMessage*: Uint
      hIcon*: Hicon
      szTip*: array[128, Utf16Char]
      dwState*: Dword
      dwStateMask*: Dword
      szInfo*: array[256, Utf16Char]
      uVersion*: Uint
      szInfoTitle*: array[64, Utf16Char]
      dwInfoFlags*: Dword
      guidItem*: Guid
      hBalloonIcon*: Hicon
else:
  type
    Point* = object
      x*: Long
      y*: Long

    Size* = object
      cx*: Long
      cy*: Long

    Rect* = object
      left*: Long
      top*: Long
      right*: Long
      bottom*: Long

    Msg* = object
      hwnd*: Hwnd
      message*: Uint
      wParam*: Wparam
      lParam*: Lparam
      time*: Dword
      pt*: Point

    WndClassExW* = object
      cbSize*: Uint
      style*: Uint
      lpfnWndProc*: WndProc
      cbClsExtra*: Int
      cbWndExtra*: Int
      hInstance*: Hinstance
      hIcon*: Hicon
      hCursor*: Hcursor
      hbrBackground*: Hbrush
      lpszMenuName*: Lpcwstr
      lpszClassName*: Lpcwstr
      hIconSm*: Hicon

    CreateStructW* = object
      lpCreateParams*: pointer
      hInstance*: Hinstance
      hMenu*: Hmenu
      hwndParent*: Hwnd
      cy*: Int
      cx*: Int
      y*: Int
      x*: Int
      style*: Long
      lpszName*: Lpcwstr
      lpszClass*: Lpcwstr
      dwExStyle*: Dword

    MinMaxInfo* = object
      ptReserved*: Point
      ptMaxSize*: Point
      ptMaxPosition*: Point
      ptMinTrackSize*: Point
      ptMaxTrackSize*: Point

    Accel* = object
      fVirt*: Byte
      key*: Word
      cmd*: Word

    Guid* = object
      data1*: Dword
      data2*: Word
      data3*: Word
      data4*: array[8, Byte]

    NotifyIconDataW* = object
      cbSize*: Dword
      hWnd*: Hwnd
      uID*: Uint
      uFlags*: Uint
      uCallbackMessage*: Uint
      hIcon*: Hicon
      szTip*: array[128, Utf16Char]
      dwState*: Dword
      dwStateMask*: Dword
      szInfo*: array[256, Utf16Char]
      uVersion*: Uint
      szInfoTitle*: array[64, Utf16Char]
      dwInfoFlags*: Dword
      guidItem*: Guid
      hBalloonIcon*: Hicon

const
  winFalse* = Bool(0)
  winTrue* = Bool(1)

  csVRedraw* = Uint(0x0001)
  csHRedraw* = Uint(0x0002)
  csDblClks* = Uint(0x0008)

  cwUseDefault* = Int(-2147483648)

  wsOverlapped* = Dword(0x00000000)
  wsPopup* = Dword(0x80000000'u32)
  wsChild* = Dword(0x40000000)
  wsMinimize* = Dword(0x20000000)
  wsVisible* = Dword(0x10000000)
  wsDisabled* = Dword(0x08000000)
  wsClipSiblings* = Dword(0x04000000)
  wsClipChildren* = Dword(0x02000000)
  wsMaximize* = Dword(0x01000000)
  wsCaption* = Dword(0x00C00000)
  wsBorder* = Dword(0x00800000)
  wsDlgFrame* = Dword(0x00400000)
  wsVScroll* = Dword(0x00200000)
  wsHScroll* = Dword(0x00100000)
  wsSysMenu* = Dword(0x00080000)
  wsThickFrame* = Dword(0x00040000)
  wsGroup* = Dword(0x00020000)
  wsTabStop* = Dword(0x00010000)
  wsMinimizeBox* = Dword(0x00020000)
  wsMaximizeBox* = Dword(0x00010000)
  wsOverlappedWindow* = wsOverlapped or wsCaption or wsSysMenu or
      wsThickFrame or wsMinimizeBox or wsMaximizeBox

  swHide* = Int(0)
  swShow* = Int(5)

  wmCreate* = Uint(0x0001)
  wmDestroy* = Uint(0x0002)
  wmSize* = Uint(0x0005)
  wmSetFocus* = Uint(0x0007)
  wmKillFocus* = Uint(0x0008)
  wmClose* = Uint(0x0010)
  wmQuit* = Uint(0x0012)
  wmCommand* = Uint(0x0111)
  wmGetDpiScaledSize* = Uint(0x02E4)
  wmDpiChanged* = Uint(0x02E0)

  gwlUserData* = Int(-21)
  gwlStyle* = Int(-16)
  gwlpWndProc* = Int(-4)
  gwlpUserData* = Int(-21)

  pmRemove* = Uint(0x0001)

  wsExControlParent* = Dword(0x00010000)

  fvVirtKey* = Byte(0x01)
  fNoInvert* = Byte(0x02)
  fShift* = Byte(0x04)
  fControl* = Byte(0x08)
  fAlt* = Byte(0x10)

  vkTab* = Word(0x09)
  vkReturn* = Word(0x0D)
  vkEscape* = Word(0x1B)
  vkSpace* = Word(0x20)
  vkLeft* = Word(0x25)
  vkUp* = Word(0x26)
  vkRight* = Word(0x27)
  vkDown* = Word(0x28)
  vkF1* = Word(0x70)
  vkF12* = Word(0x7B)

  idcArrowValue* = 32512
  idiApplicationValue* = 32512

  wmNcCreate* = Uint(0x0081)
  wmLButtonUp* = Uint(0x0202)
  wmRButtonUp* = Uint(0x0205)
  wmApp* = Uint(0x8000)

  swpNoMove* = Uint(0x0002)
  swpNoZOrder* = Uint(0x0004)

  imageIcon* = Uint(1)
  lrLoadFromFile* = Uint(0x00000010)

  nimAdd* = Dword(0x00000000)
  nimModify* = Dword(0x00000001)
  nimDelete* = Dword(0x00000002)
  nimSetVersion* = Dword(0x00000004)
  notifyIconVersion4* = Uint(4)

  nifMessage* = Uint(0x00000001)
  nifIcon* = Uint(0x00000002)
  nifTip* = Uint(0x00000004)

  mfString* = Uint(0x00000000)
  mfGrayed* = Uint(0x00000001)
  mfDisabled* = Uint(0x00000002)
  mfChecked* = Uint(0x00000008)
  mfPopup* = Uint(0x00000010)
  mfSeparator* = Uint(0x00000800)

  tpmRightButton* = Uint(0x0002)

proc dpiAwarenessContextPerMonitorAwareV2*(): DpiAwarenessContext =
  cast[DpiAwarenessContext](-4)

proc hwndMessage*(): Hwnd =
  cast[Hwnd](-3)

proc idcArrow*(): Lpcwstr =
  cast[Lpcwstr](idcArrowValue)

proc idiApplication*(): Lpcwstr =
  cast[Lpcwstr](idiApplicationValue)

proc registerClassExW*(lpWndClass: ptr WndClassExW): Atom
  {.importc: "RegisterClassExW", header: "windows.h", stdcall.}

proc createWindowExW*(dwExStyle: Dword; lpClassName, lpWindowName: Lpcwstr;
    dwStyle: Dword; x, y, nWidth, nHeight: Int; hWndParent: Hwnd;
    hMenu: Hmenu; hInstance: Hinstance; lpParam: pointer): Hwnd
  {.importc: "CreateWindowExW", header: "windows.h", stdcall.}

proc destroyWindow*(hWnd: Hwnd): Bool
  {.importc: "DestroyWindow", header: "windows.h", stdcall.}

proc showWindow*(hWnd: Hwnd; nCmdShow: Int): Bool
  {.importc: "ShowWindow", header: "windows.h", stdcall.}

proc updateWindow*(hWnd: Hwnd): Bool
  {.importc: "UpdateWindow", header: "windows.h", stdcall.}

proc defWindowProcW*(hWnd: Hwnd; msg: Uint; wParam: Wparam;
    lParam: Lparam): Lresult
  {.importc: "DefWindowProcW", header: "windows.h", stdcall.}

proc getMessageW*(lpMsg: ptr Msg; hWnd: Hwnd; wMsgFilterMin,
    wMsgFilterMax: Uint): Bool
  {.importc: "GetMessageW", header: "windows.h", stdcall.}

proc peekMessageW*(lpMsg: ptr Msg; hWnd: Hwnd; wMsgFilterMin,
    wMsgFilterMax, wRemoveMsg: Uint): Bool
  {.importc: "PeekMessageW", header: "windows.h", stdcall.}

proc translateMessage*(lpMsg: ptr Msg): Bool
  {.importc: "TranslateMessage", header: "windows.h", stdcall.}

proc dispatchMessageW*(lpMsg: ptr Msg): Lresult
  {.importc: "DispatchMessageW", header: "windows.h", stdcall.}

proc postQuitMessage*(nExitCode: Int)
  {.importc: "PostQuitMessage", header: "windows.h", stdcall.}

proc postMessageW*(hWnd: Hwnd; msg: Uint; wParam: Wparam;
    lParam: Lparam): Bool
  {.importc: "PostMessageW", header: "windows.h", stdcall.}

proc sendMessageW*(hWnd: Hwnd; msg: Uint; wParam: Wparam;
    lParam: Lparam): Lresult
  {.importc: "SendMessageW", header: "windows.h", stdcall.}

proc getModuleHandleW*(lpModuleName: Lpcwstr): Hinstance
  {.importc: "GetModuleHandleW", header: "windows.h", stdcall.}

proc loadCursorW*(hInstance: Hinstance; lpCursorName: Lpcwstr): Hcursor
  {.importc: "LoadCursorW", header: "windows.h", stdcall.}

proc registerWindowMessageW*(lpString: Lpcwstr): Uint
  {.importc: "RegisterWindowMessageW", header: "windows.h", stdcall.}

proc loadIconW*(hInstance: Hinstance; lpIconName: Lpcwstr): Hicon
  {.importc: "LoadIconW", header: "windows.h", stdcall.}

proc loadImageW*(hinst: Hinstance; name: Lpcwstr; imageType: Uint; cx, cy: Int;
    fuLoad: Uint): pointer
  {.importc: "LoadImageW", header: "windows.h", stdcall.}

proc destroyIcon*(hIcon: Hicon): Bool
  {.importc: "DestroyIcon", header: "windows.h", stdcall.}

proc setWindowLongPtrW*(hWnd: Hwnd; nIndex: Int;
    dwNewLong: LongPtr): LongPtr
  {.importc: "SetWindowLongPtrW", header: "windows.h", stdcall.}

proc getWindowLongPtrW*(hWnd: Hwnd; nIndex: Int): LongPtr
  {.importc: "GetWindowLongPtrW", header: "windows.h", stdcall.}

proc setWindowTextW*(hWnd: Hwnd; lpString: Lpcwstr): Bool
  {.importc: "SetWindowTextW", header: "windows.h", stdcall.}

proc moveWindow*(hWnd: Hwnd; x, y, nWidth, nHeight: Int;
    bRepaint: Bool): Bool
  {.importc: "MoveWindow", header: "windows.h", stdcall.}

proc setWindowPos*(hWnd: Hwnd; hWndInsertAfter: Hwnd; x, y, cx, cy: Int;
    uFlags: Uint): Bool
  {.importc: "SetWindowPos", header: "windows.h", stdcall.}

proc getClientRect*(hWnd: Hwnd; lpRect: ptr Rect): Bool
  {.importc: "GetClientRect", header: "windows.h", stdcall.}

proc adjustWindowRectEx*(lpRect: ptr Rect; dwStyle: Dword; bMenu: Bool;
    dwExStyle: Dword): Bool
  {.importc: "AdjustWindowRectEx", header: "windows.h", stdcall.}

proc adjustWindowRectExForDpi*(lpRect: ptr Rect; dwStyle: Dword; bMenu: Bool;
    dwExStyle: Dword; dpi: Uint): Bool
  {.importc: "AdjustWindowRectExForDpi", header: "windows.h", stdcall.}

proc getDpiForWindow*(hWnd: Hwnd): Uint
  {.importc: "GetDpiForWindow", header: "windows.h", stdcall.}

proc enableNonClientDpiScaling*(hWnd: Hwnd): Bool
  {.importc: "EnableNonClientDpiScaling", header: "windows.h", stdcall.}

proc setProcessDpiAwarenessContext*(value: DpiAwarenessContext): Bool
  {.importc: "SetProcessDpiAwarenessContext", header: "windows.h", stdcall.}

proc coInitializeEx*(pvReserved: pointer; dwCoInit: Dword): Long
  {.importc: "CoInitializeEx", header: "objbase.h", stdcall.}

proc coUninitialize*()
  {.importc: "CoUninitialize", header: "objbase.h", stdcall.}

proc coTaskMemFree*(pv: pointer)
  {.importc: "CoTaskMemFree", header: "objbase.h", stdcall.}

proc shCreateMemStream*(pInit: pointer; cbInit: Uint): pointer
  {.importc: "SHCreateMemStream", header: "shlwapi.h", stdcall.}

proc createAcceleratorTableW*(lpaccl: ptr Accel; cEntries: Int): Haccel
  {.importc: "CreateAcceleratorTableW", header: "windows.h", stdcall.}

proc translateAcceleratorW*(hWnd: Hwnd; hAccTable: Haccel;
    lpMsg: ptr Msg): Int
  {.importc: "TranslateAcceleratorW", header: "windows.h", stdcall.}

proc destroyAcceleratorTable*(hAccel: Haccel): Bool
  {.importc: "DestroyAcceleratorTable", header: "windows.h", stdcall.}

proc shellNotifyIconW*(dwMessage: Dword; lpData: ptr NotifyIconDataW): Bool
  {.importc: "Shell_NotifyIconW", header: "shellapi.h", stdcall.}

proc createPopupMenu*(): Hmenu
  {.importc: "CreatePopupMenu", header: "windows.h", stdcall.}

proc destroyMenu*(hMenu: Hmenu): Bool
  {.importc: "DestroyMenu", header: "windows.h", stdcall.}

proc appendMenuW*(hMenu: Hmenu; uFlags: Uint; uIDNewItem: UintPtr;
    lpNewItem: Lpcwstr): Bool
  {.importc: "AppendMenuW", header: "windows.h", stdcall.}

proc trackPopupMenu*(hMenu: Hmenu; uFlags: Uint; x, y, nReserved: Int;
    hWnd: Hwnd; prcRect: pointer): Bool
  {.importc: "TrackPopupMenu", header: "windows.h", stdcall.}

proc setForegroundWindow*(hWnd: Hwnd): Bool
  {.importc: "SetForegroundWindow", header: "windows.h", stdcall.}

proc getCursorPos*(lpPoint: ptr Point): Bool
  {.importc: "GetCursorPos", header: "windows.h", stdcall.}
