# Release Checklist

## Package Pins

- `viewy.nimble`: `jsony == 1.1.6`, `zippy == 0.10.19`.
- `cli/viewy_cli.nimble`: `jsony == 1.1.6`, `zippy == 0.10.19`.
- Examples: `jsony == 1.1.6`, `zippy == 0.10.19`.
- `vendor/webview/PIN`: upstream `webview/webview` tag `0.12.0`; retained
  for the compatibility `-d:viewyBackend=lite` backend.
- `vendor/webview2/PIN`: `Microsoft.Web.WebView2` `1.0.4022.49`;
  `viewy/backend/windows_webview2_pin.nim` reads this file at compile time as
  `WIN_WEBVIEW2_PIN`, and it is the shared ABI source for both the lite
  WebView2 builtin implementation and native Windows COM declarations.

## Native Platform Baselines

- Linux native backend: GTK3 plus `webkit2gtk-4.1 >= 2.40`; install
  `libgtk-3-dev` and `libwebkit2gtk-4.1-dev` on Debian/Ubuntu runners.
- Linux tray support: `libayatana-appindicator3` is a soft dependency. Release
  CI must continue to pass when it is absent, and manual tray QA needs a
  StatusNotifier/AppIndicator host when checking the positive icon path.
- Windows native backend: Microsoft Edge WebView2 Evergreen Runtime must be
  present at runtime. The SDK/COM ABI remains pinned by `vendor/webview2/PIN`.
- macOS native backend: release builds should still produce a bundle that can
  be ad-hoc signed by the CLI build pipeline.

## Name Check

- `viewy` and `viewy_cli` were not present in `nim-lang/packages` when checked
  against `packages.json` on 2026-06-13.
- Re-run the name check immediately before publishing:

```bash
curl -fsSL https://raw.githubusercontent.com/nim-lang/packages/master/packages.json |
  rg '"name"\s*:\s*"(viewy|viewy_cli)"'
```

No output means the names are still unclaimed.

## Local Gates

```bash
nimble check
(cd cli && nimble check)
nimble pretty
git diff --exit-code
nimble test -y
(cd cli && nimble test -y)
```

Native baseline probes:

```bash
pkg-config --atleast-version=2.40 webkit2gtk-4.1
nim c -r --hints:off --mm:orc --threads:on tests/native/test_windows_webview2_pin.nim
nim c --hints:off --mm:orc --threads:on -d:viewyBackend=native -o:build/test_linux_backend tests/native/test_linux_backend.nim
VIEWY_NATIVE_LINUX_SMOKE=1 xvfb-run -a build/test_linux_backend
nim c -r --hints:off --mm:orc --threads:on -d:viewyBackend=native tests/native/test_linux_appindicator.nim
```

## Clean Install Smoke

From a fresh checkout, install both packages into an isolated Nimble directory
and verify the installed CLI can scaffold a template:

```bash
tmp=$(mktemp -d)
repo="$tmp/repo"
nimbledir="$tmp/nimble"
git clone https://github.com/mattsp1290/viewy.git "$repo"
cd "$repo"
nimble --nimbleDir:"$nimbledir" install -y
cd cli
nimble --nimbleDir:"$nimbledir" install -y
"$nimbledir/bin/viewy" init smoke-app --template vanilla
cd smoke-app
npm ci
"$nimbledir/bin/viewy" build --release
test -f build/viewy_assets.nim
```

## Publish Steps

1. Update `CHANGELOG.md` date for `0.2.0`.
2. Create and push tag `v0.2.0`.
3. Publish `viewy` from the repository root with `nimble publish`.
4. Publish `viewy_cli` from `cli/` with `nimble publish`.
5. Install from Nimble into a clean directory and run `viewy init smoke-app`.
