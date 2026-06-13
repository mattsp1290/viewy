# Release Checklist

## Package Pins

- `viewy.nimble`: `jsony == 1.1.6`, `zippy == 0.10.19`.
- `cli/viewy_cli.nimble`: `jsony == 1.1.6`, `zippy == 0.10.19`.
- Examples: `jsony == 1.1.6`, `zippy == 0.10.19`.
- `vendor/webview/PIN`: upstream `webview/webview` tag `0.12.0`.
- `vendor/webview2/PIN`: `Microsoft.Web.WebView2` `1.0.4022.49`.

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
```

## Publish Steps

1. Update `CHANGELOG.md` date for `0.1.0`.
2. Create and push tag `v0.1.0`.
3. Publish `viewy` from the repository root with `nimble publish`.
4. Publish `viewy_cli` from `cli/` with `nimble publish`.
5. Install from Nimble into a clean directory and run `viewy init smoke-app`.
