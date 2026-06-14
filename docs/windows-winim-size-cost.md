# Windows winim Size-Cost Decision

Bead: `viewy-cqq`
Date: 2026-06-14

## Decision

Keep the Windows native backend on the current hand-written Win32 and COM FFI
surface. Do not add `winim` as a dependency or rewrite the current backend
around it.

The executable measurement below shows that a small `winim` import is not
disqualified by binary size on its own. The current backend still stays
hand-written because it already exists, avoids a broad third-party Windows API
surface, and keeps the dependency list smaller.

The concrete acceptance threshold for reconsidering `winim` in production
backend code is:

- The vanilla template release binary built on Windows must remain below
  `3 * 1024 * 1024` bytes, matching `MaxReleaseBinaryBytes` in
  `cli/tests/test_e2e.nim`.
- The `winim` variant must increase the same Windows release binary by no more
  than `256 * 1024` bytes over the hand-written backend baseline.
- The measurement must produce a Windows AMD64 `.exe` with the same release
  flags used by `viewy build --release`: `-d:release -d:strip --opt:size
  --mm:orc --threads:on`.

The standalone Windows-target samples below pass this threshold. A future
backend rewrite or substantial new Windows API surface must repeat the
measurement against the actual vanilla app before adding `winim`.

## Executable Measurement

The measurement used Homebrew `mingw-w64` 14.0.0
(`x86_64-w64-mingw32-gcc`) to produce Windows AMD64 executables from this
macOS host.

Installed package and toolchain:

```text
winim 3.9.4
Nim 2.2.10
mingw-w64 14.0.0
package directory size: 9.2 MiB
Nim source total: 142,158 lines
```

Compile command shape:

```bash
nim c --hints:off --os:windows --cpu:amd64 --cc:gcc \
  --gcc.exe:x86_64-w64-mingw32-gcc \
  --gcc.linkerexe:x86_64-w64-mingw32-gcc \
  --mm:orc --threads:on -d:release -d:strip --opt:size \
  -o:sample.exe sample.nim
```

Results:

| Sample | Import | `.exe` bytes | Delta vs hand-written |
| --- | --- | ---: | ---: |
| handwritten | none; local `GetModuleHandleW`/`MessageBoxW` imports | 95,232 | baseline |
| winim_lean | `winim/lean` | 101,376 | +6,144 |
| winim_mean | `winim/mean` | 101,376 | +6,144 |
| winim_com | `winim/com` | 112,128 | +16,896 |

All four samples are below the 3 MiB hard budget, and the largest observed
`winim` delta is 16,896 bytes, below the 256 KiB delta budget.

Sample sources:

```nim
# handwritten.nim
type
  Hwnd = pointer
  Hinstance = pointer
  Uint = cuint
  Int = cint
  Lpcwstr = WideCString

proc getModuleHandleW(lpModuleName: Lpcwstr): Hinstance
  {.importc: "GetModuleHandleW", header: "windows.h", stdcall.}
proc messageBoxW(hWnd: Hwnd; lpText, lpCaption: Lpcwstr; uType: Uint): Int
  {.importc: "MessageBoxW", header: "windows.h", stdcall.}

when isMainModule:
  discard getModuleHandleW(nil)
  discard messageBoxW(nil, newWideCString("Viewy"), newWideCString("Viewy"), 0)
```

```nim
# winim_lean.nim
import winim/lean

when isMainModule:
  discard GetModuleHandle(nil)
  discard MessageBox(0, "Viewy", "Viewy", 0)
```

```nim
# winim_mean.nim
import winim/mean

when isMainModule:
  discard GetModuleHandle(nil)
  discard MessageBox(0, "Viewy", "Viewy", 0)
  var nid: NOTIFYICONDATA
  nid.cbSize = sizeof(NOTIFYICONDATA).DWORD
  discard nid.cbSize
```

```nim
# winim_com.nim
import winim/com

when isMainModule:
  discard GetModuleHandle(nil)
  discard MessageBox(0, "Viewy", "Viewy", 0)
  discard CoInitializeEx(nil, COINIT_APARTMENTTHREADED)
  CoUninitialize()
```

## Compile-Only Surface Measurement

For comparison, I also measured generated C/H cache size for Windows-target
compile-only builds from a clean cache:

```bash
nim check --hints:off --os:windows sample.nim
nim c --hints:off --os:windows --mm:orc --threads:on \
  -d:release -d:strip --opt:size --compileOnly sample.nim
```

| Sample | Import | `nim check` | Generated C/H files | Generated C/H bytes |
| --- | --- | ---: | ---: | ---: |
| baseline | none | pass | 7 | 195,494 |
| winim_lean | `winim/lean` | pass | 8 | 196,853 |
| winim_mean | `winim/mean` | pass | 8 | 196,853 |
| winim_com | `winim/com` | pass | 12 | 302,746 |

The compile-only proxy does not show a large generated-code increase for unused
declarations, but it also does not measure link output, resource payloads,
debug/linker metadata, or a real app importing enough APIs to replace the
current backend. The package itself is much larger than the hand-written FFI
surface and would add a broad Windows API dependency to the project.

## Required App-Level Follow-Up

If `winim` is reconsidered later for production backend code, run an app-level
measurement on a Windows runner or VM with MinGW or MSVC. Do not rely on the
current `viewy build --release` backend default for this comparison: today the
CLI can select `-d:viewyBackend=lite` for scheme assets on Windows. Force the
native backend explicitly in both variants.

1. Build the vanilla template with the current hand-written backend:
   `nim c --mm:orc --threads:on -d:release -d:strip --opt:size
   -d:viewyBackend=native ...`.
2. Build an otherwise identical branch that replaces the Windows backend FFI
   dependency with the narrowest plausible `winim` import level, using the same
   explicit native-backend flags.
3. Record both `build/demo-app.exe` sizes and the exact compiler, linker, Nim,
   `winim`, and WebView2 SDK versions.
4. Accept only if both the 3 MiB hard budget and 256 KiB delta budget pass.

This keeps the project aligned with the native-backend constraint that Windows
defaults to minimal hand-written Win32 plus COM declarations.
